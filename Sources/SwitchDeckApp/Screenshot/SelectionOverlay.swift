import AppKit

enum CaptureRequest {
    case region(rect: CGRect, screen: NSScreen)
    case window(id: CGWindowID)
}

/// Dims every display and turns the next drag or click into a capture request.
@MainActor
final class SelectionController {
    private var windows: [SelectionWindow] = []
    private var requestHandler: ((CaptureRequest) -> Void)?
    private var cancelHandler: (() -> Void)?

    private(set) var isActive = false

    func begin(
        onSelect: @escaping (CaptureRequest) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard !isActive else { return }
        isActive = true
        requestHandler = onSelect
        cancelHandler = onCancel

        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            let view = SelectionView(screen: screen)
            view.onSelect = { [weak self] request in self?.finish(request) }
            view.onCancel = { [weak self] in self?.finish(nil) }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ request: CaptureRequest?) {
        guard isActive else { return }
        isActive = false

        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()

        if let request {
            requestHandler?(request)
        } else {
            cancelHandler?()
        }
        requestHandler = nil
        cancelHandler = nil
    }
}

private final class SelectionWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionView: NSView {
    let screen: NSScreen
    var onSelect: ((CaptureRequest) -> Void)?
    var onCancel: (() -> Void)?

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var hovered: (id: CGWindowID, rect: CGRect)?

    init(screen: NSScreen) {
        self.screen = screen
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("SelectionView is created in code only")
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        if let selection = selectionRect, selection.width > 1, selection.height > 1 {
            path.append(NSBezierPath(rect: selection))
            path.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.32).setFill()
        path.fill()

        if let selection = selectionRect, selection.width > 1 {
            let stroke = NSBezierPath(rect: selection)
            stroke.lineWidth = 1
            NSColor.controlAccentColor.setStroke()
            stroke.stroke()

            drawLabel(sizeText(for: selection), above: selection)
        } else if let hovered, dragStart == nil {
            let stroke = NSBezierPath(rect: hovered.rect)
            stroke.lineWidth = 1
            stroke.setLineDash([5, 4], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            stroke.stroke()
        }

        if dragStart == nil {
            drawHint()
        }
    }

    private func drawLabel(_ text: String, above rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let padding = NSSize(width: 7, height: 3)

        var origin = NSPoint(
            x: rect.minX,
            y: rect.maxY + 6
        )
        if origin.y + size.height + padding.height * 2 > bounds.maxY {
            origin.y = rect.minY - size.height - padding.height * 2 - 6
        }
        if origin.y < bounds.minY {
            origin.y = rect.minY + 6
        }

        let background = NSRect(
            x: origin.x,
            y: origin.y,
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()
        string.draw(at: NSPoint(x: origin.x + padding.width, y: origin.y + padding.height))
    }

    private func drawHint() {
        let text = NSAttributedString(
            string: "Drag to select · click a window · Esc to cancel",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]
        )
        let size = text.size()
        let origin = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(
            roundedRect: NSRect(
                x: origin.x - 14,
                y: origin.y - 8,
                width: size.width + 28,
                height: size.height + 16
            ),
            xRadius: 8,
            yRadius: 8
        ).fill()
        text.draw(at: origin)
    }

    private func sizeText(for rect: CGRect) -> String {
        let scale = screen.backingScaleFactor
        return "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
    }

    // MARK: - Mouse

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let rect = clampedSelectionRect

        defer {
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
        }

        if rect.width < 4 || rect.height < 4 {
            if let hovered = windowUnderMouse(point) {
                onSelect?(.window(id: hovered.id))
            } else {
                onCancel?()
            }
            return
        }

        let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        onSelect?(.region(rect: global, screen: screen))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        }
    }

    // MARK: - Geometry

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }

    private var clampedSelectionRect: CGRect {
        guard let rect = selectionRect else { return .zero }
        return rect.intersection(bounds)
    }

    private func updateHover(at point: CGPoint) {
        guard dragStart == nil else { return }
        hovered = windowUnderMouse(point)
        needsDisplay = true
    }

    /// Finds the frontmost normal window under a point, in this view's space.
    private func windowUnderMouse(_ point: CGPoint) -> (id: CGWindowID, rect: CGRect)? {
        let global = CGPoint(
            x: point.x + screen.frame.minX,
            y: point.y + screen.frame.minY
        )
        let mainHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let topLeftPoint = CGPoint(x: global.x, y: mainHeight - global.y)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID else { continue }
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            guard rect.width >= 60, rect.height >= 60, rect.contains(topLeftPoint) else { continue }

            let local = CGRect(
                x: rect.minX - screen.frame.minX,
                y: (mainHeight - rect.maxY) - screen.frame.minY,
                width: rect.width,
                height: rect.height
            )
            let id = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            return (id, local)
        }
        return nil
    }
}
