import AppKit
import SwiftUI

/// In-place screenshot editing, HapiGo style: the selection stays on screen,
/// everything outside it dims, and the toolbar appears right under the region.
/// Nothing is captured until the user copies, saves or pins.
@MainActor
final class SelectionController {
    private var windows: [SelectionWindow] = []
    private var captureHandler: ((CGRect, NSScreen, [Annotation], CaptureSession.Output) -> Void)?
    private var cancelHandler: (() -> Void)?

    let session = CaptureSession()
    private(set) var isActive = false

    func begin(
        onCapture: @escaping (CGRect, NSScreen, [Annotation], CaptureSession.Output) -> Void,
        onCancel: @escaping () -> Void,
        initialSelection: CGRect? = nil
    ) {
        guard !isActive else { return }
        isActive = true
        captureHandler = onCapture
        cancelHandler = onCancel
        session.annotations = []

        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            let view = SelectionView(screen: screen, session: session)
            view.onCapture = { [weak self] rect, screen, annotations, output in
                self?.finish(rect: rect, screen: screen, annotations: annotations, output: output)
            }
            view.onCancel = { [weak self] in
                self?.finish(rect: nil, screen: nil, annotations: [], output: .copy)
            }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)

            if let initialSelection {
                let local = initialSelection.offsetBy(
                    dx: -screen.frame.minX,
                    dy: -screen.frame.minY
                )
                if local.intersects(NSRect(origin: .zero, size: screen.frame.size)) {
                    view.presetSelection(local)
                }
            }
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    /// Debug helper: completes the current selection as if Enter was pressed.
    func completeForDebug(_ output: CaptureSession.Output = .copy) {
        for window in windows {
            guard let view = window.contentView as? SelectionView, view.hasSelectionForDebug else { continue }
            view.finishForDebug(output)
            return
        }
    }

    private func finish(
        rect: CGRect?,
        screen: NSScreen?,
        annotations: [Annotation],
        output: CaptureSession.Output
    ) {
        guard isActive else { return }
        isActive = false

        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()

        if let rect, let screen {
            captureHandler?(rect, screen, annotations, output)
        } else {
            cancelHandler?()
        }
        captureHandler = nil
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
        case drawing

        var isIdle: Bool {
            if case .none = self { return true }
            return false
        }
    }

    let screen: NSScreen
    let session: CaptureSession

    var onCapture: ((CGRect, NSScreen, [Annotation], CaptureSession.Output) -> Void)?
    var onCancel: (() -> Void)?

    private var selection: CGRect?
    private var interaction: Interaction = .none
    private var hovered: (id: CGWindowID, rect: CGRect)?
    private var editing = false

    private var startPoint: CGPoint?
    private var draft: Annotation?
    private var penPoints: [CGPoint] = []

    private var toolbarHost: NSHostingView<CaptureToolbarView>?
    private var textField: NSTextField?
    private var textAnchor: CGPoint = .zero
    private var keyMonitor: Any?

    init(screen: NSScreen, session: CaptureSession) {
        self.screen = screen
        self.session = session
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
        NSColor.black.withAlphaComponent(editing ? 0.42 : 0.32).setFill()
        path.fill()

        guard let selection else {
            drawHint("Drag to select · click a window · F for the whole screen · R for last region")
            return
        }

        if editing {
            drawAnnotations(in: selection)
            let stroke = NSBezierPath(rect: selection)
            stroke.lineWidth = 1
            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
            stroke.stroke()
        } else {
            let stroke = NSBezierPath(rect: selection)
            stroke.lineWidth = 1
            NSColor.controlAccentColor.setStroke()
            stroke.stroke()

            drawHandles(for: selection)
            drawLabel(sizeText(for: selection), above: selection)
            drawHint("Enter or drag to edit · R reuses the last region · Esc cancels")
        }
    }

    private func drawAnnotations(in rect: CGRect) {
        for annotation in session.annotations {
            AnnotationRenderer.draw(annotation, in: rect, base: nil)
        }
        if let draft {
            AnnotationRenderer.draw(draft, in: rect, base: nil)
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
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.minY + 42)
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

    // MARK: - Editing lifecycle

    var hasSelectionForDebug: Bool { selection != nil }

    func finishForDebug(_ output: CaptureSession.Output) {
        finish(output)
    }

    func presetSelection(_ rect: CGRect) {
        selection = clamp(rect)
        startEditing()
    }

    private func startEditing() {
        guard selection != nil, !editing else { return }
        editing = true
        session.annotations = []
        session.onUndo = { [weak self] in
            guard let self, !self.session.annotations.isEmpty else { return }
            self.session.annotations.removeLast()
            self.needsDisplay = true
        }
        session.onCopy = { [weak self] in self?.finish(.copy) }
        session.onSave = { [weak self] in self?.finish(.save) }
        session.onPin = { [weak self] in self?.finish(.pin) }
        session.onClose = { [weak self] in self?.onCancel?() }

        installToolbar()
        installKeyMonitor()
        needsDisplay = true
    }

    /// Enter/Space/P work even when the toolbar has focus, because the local
    /// monitor sees the keys before SwiftUI does.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.editing, self.window?.isKeyWindow == true else { return event }
            if self.window?.firstResponder is NSTextView { return event }

            switch event.keyCode {
            case 53: // Esc
                self.onCancel?()
                return nil
            case 36, 76: // Return
                self.finish(.copy)
                return nil
            case 49: // Space
                self.finish(.save)
                return nil
            case 35: // P
                self.finish(.pin)
                return nil
            case 6 where event.modifierFlags.contains(.command): // ⌘Z
                if !self.session.annotations.isEmpty {
                    self.session.annotations.removeLast()
                    self.needsDisplay = true
                }
                return nil
            default:
                return event
            }
        }
    }

    private func teardown() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        removeToolbar()
        removeTextField()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            teardown()
        }
    }

    private func finish(_ output: CaptureSession.Output) {
        guard let selection else { return }
        let global = selection.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        teardown()
        onCapture?(global, screen, session.annotations, output)
    }

    private func installToolbar() {
        guard toolbarHost == nil else { return }
        let host = NSHostingView(rootView: CaptureToolbarView(session: session))
        host.frame.size = host.fittingSize
        addSubview(host)
        toolbarHost = host
        layoutToolbar()
    }

    private func layoutToolbar() {
        guard let toolbarHost, let selection else { return }
        let size = toolbarHost.fittingSize
        let gap: CGFloat = 10

        var x = selection.midX - size.width / 2
        x = min(max(8, x), bounds.width - size.width - 8)

        var y = selection.minY - size.height - gap
        if y < 8 {
            y = min(bounds.height - size.height - 8, selection.maxY + gap)
        }

        toolbarHost.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func removeToolbar() {
        toolbarHost?.removeFromSuperview()
        toolbarHost = nil
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

        if editing {
            if let selection, let handle = handle(at: point, in: selection) {
                interaction = .resizing(handle: handle, rect: selection)
                return
            }
            if let selection, selection.contains(point) {
                interaction = .drawing
                startPoint = normalize(point, in: selection)
                penPoints = []
                if session.tool == .text {
                    showTextField(at: point)
                    interaction = .none
                }
                return
            }
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
            selection = clamp(rect(from: start, to: point))

        case .moving(let start, let rect):
            let offset = CGPoint(x: point.x - start.x, y: point.y - start.y)
            selection = clamp(rect.offsetBy(dx: offset.x, dy: offset.y))
            layoutToolbar()

        case .resizing(let handle, let rect):
            selection = clamp(resized(rect, handle: handle, to: point))
            layoutToolbar()

        case .drawing:
            guard let selection, let start = startPoint else { return }
            let current = normalize(point, in: selection)
            updateDraft(from: start, to: current)

        case .none:
            break
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let previous = interaction
        interaction = .none
        defer { needsDisplay = true }

        switch previous {
        case .creating:
            if let selection, selection.width >= 4, selection.height >= 4 {
                startEditing()
            } else {
                self.selection = nil
                if let hovered = windowUnderMouse(point) {
                    selection = hovered.rect
                    startEditing()
                } else {
                    onCancel?()
                }
            }

        case .drawing:
            guard let selection, let start = startPoint else { return }
            let end = normalize(point, in: selection)

            switch session.tool {
            case .text:
                break
            case .number:
                if hypot(end.x - start.x, end.y - start.y) * selection.width < 4 {
                    commit(.number(nextNumber, at: end))
                }
            case .pen, .highlighter:
                commit(session.tool == .pen ? .pen(points: penPoints) : .highlighter(points: penPoints))
            default:
                commit(draftShape(from: start, to: end))
            }
            draft = nil
            penPoints = []

        default:
            break
        }
    }

    private func updateDraft(from start: CGPoint, to current: CGPoint) {
        switch session.tool {
        case .pen, .highlighter:
            penPoints.append(current)
            draft = Annotation(
                shape: session.tool == .pen ? .pen(points: penPoints) : .highlighter(points: penPoints),
                color: session.color,
                lineWidth: session.lineWidth
            )
        case .text, .number:
            break
        default:
            draft = Annotation(
                shape: draftShape(from: start, to: current),
                color: session.color,
                lineWidth: session.lineWidth
            )
        }
    }

    private func draftShape(from start: CGPoint, to end: CGPoint) -> Annotation.Shape {
        switch session.tool {
        case .rectangle: return .rectangle(from: start, to: end)
        case .ellipse: return .ellipse(from: start, to: end)
        case .line: return .line(from: start, to: end)
        case .mosaic: return .mosaic(from: start, to: end)
        case .blur: return .blur(from: start, to: end)
        default: return .arrow(from: start, to: end)
        }
    }

    private var nextNumber: Int {
        session.annotations.reduce(1) { count, annotation in
            if case .number = annotation.shape { return count + 1 }
            return count
        }
    }

    private func commit(_ shape: Annotation.Shape) {
        session.annotations.append(Annotation(
            shape: shape,
            color: session.color,
            lineWidth: session.lineWidth,
            textScale: session.textScale,
            textBubble: session.textBubble,
            arrowStyle: session.arrowStyle
        ))
    }

    // MARK: - Text entry

    private func showTextField(at point: CGPoint) {
        removeTextField()
        textAnchor = point

        let field = NSTextField(frame: NSRect(x: point.x, y: point.y - 12, width: 200, height: 24))
        field.placeholderString = "Text"
        field.font = .systemFont(ofSize: 13)
        field.target = self
        field.action = #selector(commitText)
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    @objc private func commitText() {
        guard let field = textField, let selection else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            commit(.text(text, at: normalize(textAnchor, in: selection)))
        }
        removeTextField()
        needsDisplay = true
    }

    private func removeTextField() {
        textField?.removeFromSuperview()
        textField = nil
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if editing {
            switch event.keyCode {
            case 53: onCancel?()                                  // Esc
            case 36, 76: finish(.copy)                            // Return
            case 49: finish(.save)                                // Space
            case 35: finish(.pin)                                 // P
            case 6 where event.modifierFlags.contains(.command):  // ⌘Z
                if !session.annotations.isEmpty {
                    session.annotations.removeLast()
                    needsDisplay = true
                }
            default: break
            }
            return
        }

        switch event.keyCode {
        case 53:
            if selection != nil {
                selection = nil
                needsDisplay = true
            } else {
                onCancel?()
            }
        case 36, 76:
            if selection != nil {
                startEditing()
            } else {
                selection = bounds
                startEditing()
            }
        case 3:
            selection = bounds
            startEditing()
        case 15:
            if let last = SelectionMemory.lastSelection {
                selection = clamp(last.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY))
                needsDisplay = true
            }
        default:
            break
        }
    }

    // MARK: - Geometry

    private func normalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(1, max(0, (point.x - rect.minX) / max(1, rect.width))),
            y: min(1, max(0, (rect.maxY - point.y) / max(1, rect.height)))
        )
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
            if box.insetBy(dx: -4, dy: -4).contains(point) { return handle }
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
            x: min(minX, maxX), y: min(minY, maxY),
            width: abs(maxX - minX), height: abs(maxY - minY)
        )
    }

    private func updateHover(at point: CGPoint) {
        guard !editing, selection == nil, interaction.isIdle else { return }
        hovered = windowUnderMouse(point)
        needsDisplay = true
    }

    private var primaryHeight: CGFloat {
        if let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return primary.frame.height
        }
        return NSScreen.main?.frame.height ?? NSScreen.screens.first?.frame.height ?? 0
    }

    private func windowUnderMouse(_ point: CGPoint) -> (id: CGWindowID, rect: CGRect)? {
        let global = CGPoint(x: point.x + screen.frame.minX, y: point.y + screen.frame.minY)
        let mainHeight = primaryHeight
        let topLeftPoint = CGPoint(x: global.x, y: mainHeight - global.y)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

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
            return (info[kCGWindowNumber as String] as? CGWindowID ?? 0, local)
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
