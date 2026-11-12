import AppKit

enum CaptureRequest {
    case region(rect: CGRect, screen: NSScreen)
    case window(id: CGWindowID)
}

/// Dims every display, lets the user shape a region with handles, then turns
/// Enter (or a double click) into a capture request.
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
    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum Interaction {
        case none
        case creating(start: CGPoint)
        case moving(start: CGPoint, rect: CGRect)
        case resizing(handle: Handle, rect: CGRect)

        var isIdle: Bool {
            if case .none = self { return true }
            return false
        }
    }

    let screen: NSScreen
    var onSelect: ((CaptureRequest) -> Void)?
    var onCancel: (() -> Void)?

    private var selection: CGRect?
    private var interaction: Interaction = .none
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
        if let selection, selection.width > 1, selection.height > 1 {
            path.append(NSBezierPath(rect: selection))
            path.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.32).setFill()
        path.fill()

        if let selection, selection.width > 1, selection.height > 1 {
            let stroke = NSBezierPath(rect: selection)
            stroke.lineWidth = 1
            NSColor.controlAccentColor.setStroke()
            stroke.stroke()

            drawHandles(for: selection)
            drawLabel(sizeText(for: selection), above: selection)
            drawHint("Enter to capture · drag a handle to adjust · Esc to clear")
        } else if let hovered, interaction.isIdle {
            let stroke = NSBezierPath(rect: hovered.rect)
            stroke.lineWidth = 1
            stroke.setLineDash([5, 4], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            stroke.stroke()
            drawHint("Drag to select · click a window · F for the whole screen · R for last region")
        } else {
            drawHint("Drag to select · click a window · F for the whole screen · R for last region")
        }
    }

    private func drawHandles(for rect: CGRect) {
        NSColor.white.setFill()
        NSColor.controlAccentColor.setStroke()

        for handleRect in handleRects(for: rect).values {
            let path = NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2)
            path.lineWidth = 1.5
            path.fill()
            path.stroke()
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

        var origin = NSPoint(x: rect.minX, y: rect.maxY + 8)
        if origin.y + size.height + padding.height * 2 > bounds.maxY {
            origin.y = rect.minY - size.height - padding.height * 2 - 8
        }
        if origin.y < bounds.minY {
            origin.y = rect.minY + 8
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

    private func drawHint(_ text: String) {
        let string = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ]
        )
        let size = string.size()
        let origin = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.minY + 42
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
        string.draw(at: origin)
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
        let point = convert(event.locationInWindow, from: nil)

        if event.clickCount == 2, let selection, selection.contains(point) {
            confirm()
            return
        }

        if let selection {
            if let handle = handle(at: point, in: selection) {
                interaction = .resizing(handle: handle, rect: selection)
                return
            }
            if selection.contains(point) {
                interaction = .moving(start: point, rect: selection)
                return
            }
        }

        selection = nil
        interaction = .creating(start: point)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch interaction {
        case .creating(let start):
            selection = rect(from: start, to: point)

        case .moving(let start, let rect):
            let offset = CGPoint(x: point.x - start.x, y: point.y - start.y)
            selection = clamp(rect.offsetBy(dx: offset.x, dy: offset.y))

        case .resizing(let handle, let rect):
            selection = clamp(resized(rect, handle: handle, to: point))

        case .none:
            break
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let wasCreating: Bool
        if case .creating = interaction { wasCreating = true } else { wasCreating = false }
        interaction = .none

        defer { needsDisplay = true }

        if wasCreating, let selection, selection.width < 4 || selection.height < 4 {
            self.selection = nil

            if let hovered = windowUnderMouse(point) {
                onSelect?(.window(id: hovered.id))
            } else {
                onCancel?()
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc: clear the selection first, then leave.
            if selection != nil {
                selection = nil
                needsDisplay = true
            } else {
                onCancel?()
            }
        case 36, 76: // Return / keypad Enter
            if selection != nil {
                confirm()
            } else {
                onSelect?(.region(rect: screen.frame, screen: screen))
            }
        case 3: // F: whole screen
            onSelect?(.region(rect: screen.frame, screen: screen))
        case 15: // R: reuse the last region
            if let last = SelectionMemory.lastSelection {
                selection = clamp(last.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY))
                needsDisplay = true
            }
        default:
            break
        }
    }

    // MARK: - Geometry

    private func confirm() {
        guard let selection, selection.width > 4, selection.height > 4 else { return }
        let global = selection.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        SelectionMemory.save(global)
        onSelect?(.region(rect: global, screen: screen))
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    private func clamp(_ rect: CGRect) -> CGRect {
        rect.intersection(bounds)
    }

    private func handleRects(for rect: CGRect) -> [Handle: CGRect] {
        let size: CGFloat = 9
        func box(_ x: CGFloat, _ y: CGFloat) -> CGRect {
            CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
        }
        return [
            .topLeft: box(rect.minX, rect.maxY),
            .top: box(rect.midX, rect.maxY),
            .topRight: box(rect.maxX, rect.maxY),
            .right: box(rect.maxX, rect.midY),
            .bottomRight: box(rect.maxX, rect.minY),
            .bottom: box(rect.midX, rect.minY),
            .bottomLeft: box(rect.minX, rect.minY),
            .left: box(rect.minX, rect.midY),
        ]
    }

    private func handle(at point: CGPoint, in rect: CGRect) -> Handle? {
        for (handle, box) in handleRects(for: rect) {
            let hit = box.insetBy(dx: -4, dy: -4)
            if hit.contains(point) { return handle }
        }
        return nil
    }

    private func resized(_ rect: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch handle {
        case .topLeft: minX = point.x; maxY = point.y
        case .top: maxY = point.y
        case .topRight: maxX = point.x; maxY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; minY = point.y
        case .bottom: minY = point.y
        case .bottomLeft: minX = point.x; minY = point.y
        case .left: minX = point.x
        }

        return CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    private func updateHover(at point: CGPoint) {
        guard selection == nil, interaction.isIdle else { return }
        hovered = windowUnderMouse(point)
        needsDisplay = true
    }

    /// CGWindow bounds use the primary display's top-left as origin. The primary
    /// display is the one at (0,0), not necessarily the tallest screen — using
    /// `maxY` here broke window picking on multi-display setups.
    private var primaryHeight: CGFloat {
        if let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return primary.frame.height
        }
        return NSScreen.main?.frame.height ?? NSScreen.screens.first?.frame.height ?? 0
    }

    /// Finds the frontmost normal window under a point, in this view's space.
    private func windowUnderMouse(_ point: CGPoint) -> (id: CGWindowID, rect: CGRect)? {
        let global = CGPoint(
            x: point.x + screen.frame.minX,
            y: point.y + screen.frame.minY
        )
        let mainHeight = primaryHeight
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

/// Remembers the last region so `R` can reuse it, like HapiGo.
private enum SelectionMemory {
    private static let key = "ScreenshotLastSelection"

    static var lastSelection: CGRect? {
        guard let values = UserDefaults.standard.array(forKey: key) as? [Double], values.count == 4 else {
            return nil
        }
        let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        guard rect.width > 4, rect.height > 4 else { return nil }
        return rect
    }

    static func save(_ rect: CGRect) {
        UserDefaults.standard.set(
            [rect.origin.x, rect.origin.y, rect.width, rect.height],
            forKey: key
        )
    }
}
