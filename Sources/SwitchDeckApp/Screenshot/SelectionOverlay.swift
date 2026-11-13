import AppKit
import Combine
import SwiftUI
import SwitchKit

/// In-place screenshot editing: the selection stays on screen,
/// everything outside it dims, and the toolbar appears right under the region.
/// The selected pixels freeze when editing starts; output reuses that image.
@MainActor
final class SelectionController {
    private var windows: [SelectionWindow] = []
    private var captureHandler: ((CapturePayload, CaptureSession.Output) -> Void)?
    private var cancelHandler: (() -> Void)?

    let session = CaptureSession()
    private(set) var isActive = false

    /// Exclude only capture overlays, not Settings or other app windows.
    static var overlayWindowIDs: Set<CGWindowID> {
        Set(NSApp.windows.compactMap { window in
            guard window.contentView is SelectionView, window.windowNumber > 0 else { return nil }
            return CGWindowID(window.windowNumber)
        })
    }

    func begin(
        onCapture: @escaping (CapturePayload, CaptureSession.Output) -> Void,
        onCancel: @escaping () -> Void,
        captureBase: @escaping (CGRect, NSScreen) async -> CGImage?,
        captureWindows: @escaping ([CaptureWindowTarget], CGRect, NSScreen) async -> CGImage?,
        initialSelection: CGRect? = nil,
        frozen: @escaping (NSScreen) -> CGImage? = { _ in nil }
    ) {
        guard !isActive else { return }
        isActive = true
        captureHandler = onCapture
        cancelHandler = onCancel
        session.annotations = []
        session.resetHistory()

        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            let view = SelectionView(
                screen: screen,
                session: session,
                captureWindows: captureWindows,
                captureBase: captureBase,
                frozenScreen: frozen(screen)
            )
            view.onCapture = { [weak self] payload, output in
                self?.finish(payload, output)
            }
            view.onCancel = { [weak self] in
                self?.finish(nil, .copy)
            }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            view.prepareSample()

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

    func startScrollingForDebug() {
        guard ScreenshotAvailability.scrollingCapture else { return }
        for window in windows {
            (window.contentView as? SelectionView)?.startScrollingForDebug()
        }
    }

    func stopScrollingForDebug() {
        for window in windows {
            (window.contentView as? SelectionView)?.stopScrollingForDebug()
        }
    }

    /// Debug helper: completes the current selection as if Enter was pressed.
    func completeForDebug(_ output: CaptureSession.Output, extraAnnotations: [Annotation] = []) {
        for window in windows {
            guard let view = window.contentView as? SelectionView, view.hasSelectionForDebug else { continue }
            view.session.annotations.append(contentsOf: extraAnnotations)
            view.finishForDebug(output)
            return
        }
    }

    private func finish(_ payload: CapturePayload?, _ output: CaptureSession.Output) {
        guard isActive else { return }
        isActive = false

        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()

        if let payload {
            captureHandler?(payload, output)
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

final class SelectionView: NSView {
    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum Interaction {
        case none
        case creating(start: CGPoint)
        case moving(start: CGPoint, rect: CGRect)
        case resizing(handle: Handle, rect: CGRect)
        case drawing
        case movingAnnotation(start: CGPoint, index: Int, original: Annotation)
        case resizingAnnotation(handle: Handle, index: Int, original: Annotation, rect: CGRect)

        var isIdle: Bool {
            if case .none = self { return true }
            return false
        }
    }

    enum HistoryCommand: Equatable {
        case undo
        case redo
    }

    let screen: NSScreen
    let session: CaptureSession
    private let captureWindows: ([CaptureWindowTarget], CGRect, NSScreen) async -> CGImage?
    private let captureBase: (CGRect, NSScreen) async -> CGImage?
    /// A frame taken before the overlay appeared, shown in place of the live
    /// desktop so a menu or tooltip opened during the countdown survives.
    private let frozenScreen: CGImage?

    var onCapture: ((CapturePayload, CaptureSession.Output) -> Void)?
    var onCancel: (() -> Void)?

    private var selection: CGRect?
    private var interaction: Interaction = .none
    private var hovered: (id: CGWindowID, rect: CGRect)?
    /// Windows picked with ⇧-click: composited together when editing starts.
    private var windowTargets: [CaptureWindowTarget] = []
    private var editing = false
    private var baseImage: CGImage?
    private var baseTask: Task<Void, Never>?
    private var outputTask: Task<Void, Never>?
    private var isFinishing = false
    private var windowCaptureFailed = false
    private var sampleImage: CGImage?
    private var sampleRep: NSBitmapImageRep?
    private var hoverColor: NSColor?
    private var optionHeld = false
    private var colorFormat: ScreenshotPreferences.ColorFormat = ScreenshotPreferences.colorFormat
    private var scrolling: ScrollingCapture?
    private var scrollHUD: ScrollHUD?
    private var scrollCancelled = false
    private var lastMousePoint: CGPoint = .zero

    private var startPoint: CGPoint?
    private var draft: Annotation?
    private var penPoints: [CGPoint] = []

    private var toolbarHost: NSHostingView<CaptureToolbarView>?
    private var textField: NSTextField?
    private var textAnchor: CGPoint = .zero
    private var keyMonitor: Any?
    private var sessionCancellable: AnyCancellable?

    init(
        screen: NSScreen,
        session: CaptureSession,
        captureWindows: @escaping ([CaptureWindowTarget], CGRect, NSScreen) async -> CGImage? = { _, _, _ in nil },
        captureBase: @escaping (CGRect, NSScreen) async -> CGImage?,
        frozenScreen: CGImage? = nil
    ) {
        self.screen = screen
        self.session = session
        self.captureWindows = captureWindows
        self.captureBase = captureBase
        self.frozenScreen = frozenScreen
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
        // The overlay is nonopaque. Clear the previous editor bitmap before
        // drawing a live, transparent selection during scrolling capture.
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)

        // A timed capture paints the frame taken before the overlay appeared,
        // so menus and tooltips stay on screen while the region is chosen.
        if let frozenScreen {
            NSImage(cgImage: frozenScreen, size: bounds.size).draw(in: bounds)
        }

        let path = NSBezierPath(rect: bounds)
        if let selection, selection.width > 1, selection.height > 1 {
            path.append(NSBezierPath(rect: selection))
            path.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(editing ? 0.42 : 0.32).setFill()
        path.fill()

        if !editing {
            drawWindowHighlight()
        }

        guard let selection else {
            drawHint(t("Drag to select · click a window · ⇧ click adds one · F full screen · R last region"))
            drawColorReadout()
            drawColorHint()
            return
        }

        if editing {
            let resizing: Bool = {
                if case .resizing = interaction { return true }
                return false
            }()

            if !resizing, scrolling == nil {
                if let baseImage {
                    NSImage(cgImage: baseImage, size: selection.size).draw(in: selection)
                }
                drawAnnotations(in: selection)
                if let options = session.watermarkOptions, !session.watermarkHidden {
                    AnnotationRenderer.drawWatermark(options, in: selection)
                }
                drawAnnotationSelection(in: selection)
            }

            if windowTargets.isEmpty { drawHandles(for: selection) }
            let stroke = NSBezierPath(rect: selection)
            stroke.lineWidth = 1
            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
            stroke.stroke()
            if scrolling == nil {
                if windowCaptureFailed {
                    drawHint(t("The selected window could not be captured. Press Esc to try again."))
                } else {
                    drawEditingHint()
                }
            }
        } else {
            let stroke = NSBezierPath(rect: selection)
            stroke.lineWidth = 1
            NSColor.controlAccentColor.setStroke()
            stroke.stroke()

            for target in windowTargets {
                let outline = NSBezierPath(rect: target.rect)
                outline.lineWidth = 1.5
                outline.setLineDash([5, 3], count: 2, phase: 0)
                NSColor.white.withAlphaComponent(0.9).setStroke()
                outline.stroke()
            }

            if windowTargets.isEmpty { drawHandles(for: selection) }
            drawLabel(sizeText(for: selection), above: selection)

            if windowTargets.isEmpty {
                drawHint(t("Enter or drag to edit · R reuses the last region · Esc cancels"))
            } else {
                drawHint(tf("%d windows · Return to edit · Esc clears", windowTargets.count))
            }
        }

        if !editing {
            drawColorReadout()
            drawColorHint()
        }
    }

    /// Dashed accent outline over the window a click would capture.
    private func drawWindowHighlight() {
        guard let hovered, selection == nil || !windowTargets.isEmpty else { return }
        let path = NSBezierPath(rect: hovered.rect)
        path.lineWidth = 1
        path.setLineDash([5, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.withAlphaComponent(0.1).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.95).setStroke()
        path.stroke()
    }

    private func drawAnnotations(in rect: CGRect) {
        for annotation in session.annotations {
            AnnotationRenderer.draw(annotation, in: rect, base: baseImage)
        }
        if let draft {
            AnnotationRenderer.draw(draft, in: rect, base: baseImage)
        }
    }

    private func drawAnnotationSelection(in selection: CGRect) {
        guard session.tool == .select,
              let index = session.selectionIndex,
              session.annotations.indices.contains(index)
        else { return }

        let rect = viewRect(for: session.annotations[index].bounds, in: selection)
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()

        for box in handleRects(for: rect).values {
            NSColor.white.setFill()
            NSColor.controlAccentColor.setStroke()
            let handle = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
            handle.lineWidth = 1.5
            handle.fill()
            handle.stroke()
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

    private func drawColorHint() {
        let string = NSAttributedString(
            string: t("C Copy colour · ⌥ HEX / RGB / HSL"),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.8),
            ]
        )
        let size = string.size()
        let box = NSRect(x: 12, y: 12, width: size.width + 20, height: size.height + 10)
        NSColor.black.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        string.draw(at: NSPoint(x: box.minX + 10, y: box.minY + 5))
    }

    private func drawColorReadout() {
        guard let hoverColor else { return }

        let value = NSAttributedString(
            string: colorText(hoverColor),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
        )
        let scale = screen.backingScaleFactor
        let coords = String(
            format: "%d, %d",
            Int((lastMousePoint.x * scale).rounded()),
            Int(((screen.frame.height - lastMousePoint.y) * scale).rounded())
        )
        let coordinateText = NSAttributedString(
            string: coords,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.6),
            ]
        )

        let size = value.size()
        let boxSize = NSSize(width: size.width + 36, height: 36)

        var origin = NSPoint(
            x: lastMousePoint.x + 16,
            y: lastMousePoint.y - boxSize.height - 10
        )
        origin.x = min(max(4, origin.x), bounds.width - boxSize.width - 4)
        origin.y = min(max(4, origin.y), bounds.height - boxSize.height - 4)

        let box = NSRect(origin: origin, size: boxSize)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()

        let swatch = NSRect(x: box.minX + 7, y: box.midY - 5, width: 10, height: 10)
        hoverColor.setFill()
        NSBezierPath(roundedRect: swatch, xRadius: 2, yRadius: 2).fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        let border = NSBezierPath(roundedRect: swatch, xRadius: 2, yRadius: 2)
        border.lineWidth = 1
        border.stroke()

        value.draw(at: NSPoint(x: box.minX + 23, y: box.maxY - size.height - 6))
        coordinateText.draw(at: NSPoint(x: box.minX + 23, y: box.minY + 5))
    }

    private func colorText(_ color: NSColor) -> String {
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())

        switch colorFormat {
        case .hex:
            return String(format: "#%02X%02X%02X", r, g, b)
        case .rgb:
            return "R \(r) G \(g) B \(b)"
        case .hsl:
            let hsl = hslComponents(color)
            return "H \(hsl.h) S \(hsl.s) L \(hsl.l)"
        }
    }

    private func hslComponents(_ color: NSColor) -> (h: Int, s: Int, l: Int) {
        let r = color.redComponent
        let g = color.greenComponent
        let b = color.blueComponent
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let l = (maxValue + minValue) / 2
        var h: CGFloat = 0
        var s: CGFloat = 0

        if maxValue != minValue {
            let d = maxValue - minValue
            s = l > 0.5 ? d / (2 - maxValue - minValue) : d / (maxValue + minValue)
            switch maxValue {
            case r: h = (g - b) / d + (g < b ? 6 : 0)
            case g: h = (b - r) / d + 2
            default: h = (r - g) / d + 4
            }
            h /= 6
        }

        return (
            Int((h * 360).rounded()),
            Int((s * 100).rounded()),
            Int((l * 100).rounded())
        )
    }

    func prepareSample() {
        installKeyMonitor()
        guard sampleImage == nil else { return }
        let frame = screen.frame
        Task { [weak self] in
            guard let self, let image = await self.pixels(in: frame) else { return }
            self.sampleImage = image
            self.sampleRep = nil
            self.updateHoverColor(at: self.lastMousePoint)
            self.needsDisplay = true
        }
    }

    /// A timed capture crops the frame taken before the overlay appeared; a
    /// live capture goes back to ScreenCaptureKit.
    private func pixels(in global: CGRect) async -> CGImage? {
        if let frozenScreen,
           let cropped = ScreenCaptureService.crop(image: frozenScreen, to: global, screenFrame: screen.frame) {
            return cropped
        }
        return await captureBase(global, screen)
    }

    override func flagsChanged(with event: NSEvent) {
        let optionNow = event.modifierFlags.contains(.option)
        if optionNow, !optionHeld {
            colorFormat = colorFormat.next
            ScreenshotPreferences.setColorFormat(colorFormat)
            needsDisplay = true
        }
        optionHeld = optionNow
    }

    private func updateHoverColor(at point: CGPoint) {
        guard let sampleImage else {
            hoverColor = nil
            return
        }
        if let toolbarHost, toolbarHost.frame.contains(point) {
            hoverColor = nil
            return
        }
        if editing {
            hoverColor = nil
            return
        }

        if sampleRep == nil {
            sampleRep = NSBitmapImageRep(cgImage: sampleImage)
        }
        guard let rep = sampleRep, rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return }

        let scaleX = CGFloat(rep.pixelsWide) / max(1, screen.frame.width)
        let scaleY = CGFloat(rep.pixelsHigh) / max(1, screen.frame.height)
        let x = min(rep.pixelsWide - 1, max(0, Int(point.x * scaleX)))
        let y = min(rep.pixelsHigh - 1, max(0, Int((screen.frame.height - point.y) * scaleY)))

        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return }
        hoverColor = color
    }

    // MARK: - Scrolling capture

    private func startScrolling() {
        // The engine is retained for tests, but no shipping path may start it.
        guard ScreenshotAvailability.scrollingCapture,
              scrolling == nil, let selection else { return }
        scrollCancelled = false
        session.tool = .select

        let global = selection.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        let scroll = ScrollingCapture(region: global, direction: session.scrollingDirection) { [weak self] in
            guard let self else { return nil }
            return await self.pixels(in: global)
        }
        scroll.onUpdate = { [weak self] in
            guard let self, let scroll = self.scrolling else { return }
            self.scrollHUD?.update(height: scroll.totalHeight)
            self.needsDisplay = true
        }
        scroll.onNeedsOverlap = { [weak self] in
            guard let self, let scroll = self.scrolling else { return }
            self.scrollHUD?.showNeedsOverlap(height: scroll.totalHeight)
        }
        scroll.onFinish = { [weak self] image in self?.finishScrolling(image) }

        scrolling = scroll
        session.toolbarVisible = false
        layoutToolbar()

        let hud = ScrollHUD(direction: session.scrollingDirection)
        hud.onDone = { [weak self] in self?.scrolling?.stop() }
        hud.onCancel = { [weak self] in
            self?.scrollCancelled = true
            self?.scrolling?.stop()
        }
        hud.position(near: global, on: screen)
        hud.orderFrontRegardless()
        scrollHUD = hud

        // Let the wheel, clicks and drags go to the window underneath while
        // the border stays visible; the HUD is a separate window with buttons.
        window?.ignoresMouseEvents = true
        scroll.start()
        needsDisplay = true
    }

    private func finishScrolling(_ image: CGImage?) {
        guard scrolling != nil else { return }
        scrolling = nil
        window?.ignoresMouseEvents = false
        scrollHUD?.orderOut(nil)
        scrollHUD = nil
        session.toolbarVisible = true
        layoutToolbar()
        needsDisplay = true

        guard !scrollCancelled else {
            onCancel?()
            return
        }
        guard let image else {
            onCancel?()
            ColorToast.show(t("No screenshot frame was captured. Please try again."))
            return
        }

        let nsImage = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
        let saved = ScreenshotSaver.save(nsImage)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
        ColorToast.show(saved == nil
            ? t("Screenshot copied, but the file could not be saved")
            : t("Scrolling screenshot saved and copied"))
        onCancel?()
    }

    private func drawEditingHint() {
        guard let toolbarHost else { return }
        let text = t("↩ Copy · Space Save · P Pin · ⌘Z Undo · Esc Close")
        let string = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]
        )
        let size = string.size()
        let frame = toolbarHost.frame
        let origin = NSPoint(
            x: min(max(8, frame.midX - size.width / 2), bounds.width - size.width - 8),
            y: max(6, frame.minY - 22)
        )
        NSColor.black.withAlphaComponent(0.5).setFill()
        NSBezierPath(
            roundedRect: NSRect(
                x: origin.x - 10,
                y: origin.y - 4,
                width: size.width + 20,
                height: size.height + 8
            ),
            xRadius: 6,
            yRadius: 6
        ).fill()
        string.draw(at: origin)
    }

    private func sizeText(for rect: CGRect) -> String {
        let scale = screen.backingScaleFactor
        return "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
    }

    // MARK: - Editing lifecycle

    var hasSelectionForDebug: Bool { selection != nil }

    /// Read-only state for tests: scrolling capture is active or its HUD is up.
    var isScrollingCaptureActive: Bool { scrolling != nil || scrollHUD != nil }

    func finishForDebug(_ output: CaptureSession.Output) {
        finish(output)
    }

    func startScrollingForDebug() {
        startScrolling()
    }

    func stopScrollingForDebug() {
        scrolling?.stop()
    }

    func presetSelection(_ rect: CGRect) {
        windowTargets = []
        selection = clamp(rect)
        startEditing()
    }

    private func startEditing() {
        guard selection != nil, !editing else { return }
        editing = true
        session.annotations = []
        session.onUndo = { [weak self] in self?.performHistory(.undo) }
        session.onRedo = { [weak self] in self?.performHistory(.redo) }
        session.onCopy = { [weak self] in self?.finish(.copy) }
        session.onSave = { [weak self] in self?.finish(.save) }
        session.onPin = { [weak self] in self?.finish(.pin) }
        session.onClose = { [weak self] in self?.onCancel?() }
        session.onScroll = { [weak self] in
            guard ScreenshotAvailability.scrollingCapture else { return }
            self?.startScrolling()
        }

        installToolbar()
        installKeyMonitor()
        sessionCancellable = session.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.layoutToolbar()
                self?.needsDisplay = true
            }
        }
        loadBase()
        needsDisplay = true
    }

    /// Freeze the selected pixels so mosaic and blur can be shown for real.
    /// A window selection is composited from per-window captures instead of
    /// being cut out of the display, so occluding windows and shadows differ.
    private func loadBase() {
        guard let selection else { return }
        let global = selection.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        let targets = windowTargets
        baseTask?.cancel()
        windowCaptureFailed = false
        baseTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let image: CGImage?
            if targets.isEmpty {
                image = await self.pixels(in: global)
            } else {
                // Never substitute pixels from a different window or the
                // desktop when an explicitly selected window disappears.
                image = await self.captureWindows(targets, selection, self.screen)
            }
            guard !Task.isCancelled else { return }
            self.baseImage = image
            self.windowCaptureFailed = !targets.isEmpty && image == nil
            self.needsDisplay = true
        }
    }

    /// Enter/Space/P work even when the toolbar has focus, because the local
    /// monitor sees the keys before SwiftUI does.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }

            // Esc abandons a half-typed text annotation before anything else.
            if self.textField != nil, event.keyCode == 53 {
                self.removeTextField()
                self.needsDisplay = true
                return nil
            }
            if self.window?.firstResponder is NSTextView { return event }

            if self.scrolling != nil {
                switch event.keyCode {
                case 36, 76:
                    self.scrolling?.stop()
                    return nil
                case 53:
                    self.scrollCancelled = true
                    self.scrolling?.stop()
                    return nil
                default:
                    return event
                }
            }

            // Colour picking only exists while framing the region.
            if event.keyCode == 8, !self.editing {
                if let hoverColor = self.hoverColor {
                    let text = self.colorText(hoverColor)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    ColorToast.show("Copied \(text)")
                    self.onCancel?()
                    return nil
                }
                return event
            }

            guard self.editing else { return event }

            if let command = Self.historyCommand(for: event) {
                self.performHistory(command)
                return nil
            }

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
            case 51, 117: // Delete
                if self.session.tool == .select,
                   let index = self.session.selectionIndex,
                   self.session.annotations.indices.contains(index) {
                    self.session.recordUndoSnapshot()
                    self.session.annotations.remove(at: index)
                    self.session.selectionIndex = nil
                    self.needsDisplay = true
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func teardown() {
        baseTask?.cancel()
        outputTask?.cancel()
        outputTask = nil
        scrolling?.cancel()
        scrolling = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        sessionCancellable?.cancel()
        sessionCancellable = nil
        removeToolbar()
        removeTextField()
        window?.ignoresMouseEvents = false
        scrollHUD?.orderOut(nil)
        scrollHUD = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            teardown()
        }
    }

    private func finish(_ output: CaptureSession.Output) {
        guard !isFinishing else { return }
        if !windowTargets.isEmpty, let baseTask {
            isFinishing = true
            outputTask = Task { [weak self] in
                await baseTask.value
                guard !Task.isCancelled, let self else { return }
                self.outputTask = nil
                self.isFinishing = false
                self.deliver(output)
            }
        } else {
            deliver(output)
        }
    }

    private func deliver(_ output: CaptureSession.Output) {
        guard let selection else { return }
        guard windowTargets.isEmpty || baseImage != nil else {
            windowCaptureFailed = true
            needsDisplay = true
            return
        }
        let global = selection.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        let payload = CapturePayload(
            rect: global,
            screen: screen,
            annotations: session.annotations,
            base: baseImage,
            watermark: session.watermarkOptions,
            watermarkVisible: !session.watermarkHidden
        )
        teardown()
        onCapture?(payload, output)
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
        toolbarHost.isHidden = !session.toolbarVisible
    }

    private func removeToolbar() {
        toolbarHost?.removeFromSuperview()
        toolbarHost = nil
    }

    // MARK: - Mouse

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        lastMousePoint = convert(event.locationInWindow, from: nil)
        updateHoverColor(at: lastMousePoint)
        updateHover(at: lastMousePoint)
    }

    override func mouseMoved(with event: NSEvent) {
        lastMousePoint = convert(event.locationInWindow, from: nil)
        updateHoverColor(at: lastMousePoint)
        updateHover(at: lastMousePoint)
    }

    override func mouseDown(with event: NSEvent) {
        if scrolling != nil { return }
        window?.makeKey()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        commitTextFieldIfNeeded()

        if editing {
            if windowTargets.isEmpty, let selection, let handle = handle(at: point, in: selection) {
                interaction = .resizing(handle: handle, rect: selection)
                return
            }
            if let selection, selection.contains(point) {
                if session.tool == .select {
                    beginSelectionInteraction(at: point, in: selection)
                    return
                }
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

        if event.modifierFlags.contains(.shift),
           let hovered = windowUnderMouse(point) {
            toggleWindowTarget(hovered)
            return
        }

        if !windowTargets.isEmpty, let selection, selection.contains(point) {
            startEditing()
            return
        }

        if let selection {
            if windowTargets.isEmpty, let handle = handle(at: point, in: selection) {
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
        lastMousePoint = convert(event.locationInWindow, from: nil)
        updateHoverColor(at: lastMousePoint)
        let point = lastMousePoint

        switch interaction {
        case .creating(let start):
            if !windowTargets.isEmpty {
                windowTargets = []
            }
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

        case .movingAnnotation(let start, let index, let original):
            guard let selection, session.annotations.indices.contains(index) else { return }
            let delta = CGPoint(
                x: (point.x - start.x) / selection.width,
                y: -(point.y - start.y) / selection.height
            )
            session.annotations[index] = original.moved(by: delta)

        case .resizingAnnotation(let handle, let index, let original, let rect):
            guard let selection, session.annotations.indices.contains(index) else { return }
            let newViewRect = resized(rect, handle: handle, to: point)
            let newBounds = normalizedRect(newViewRect, in: selection)
            guard newBounds.width > 0.005, newBounds.height > 0.005 else { return }
            session.annotations[index] = original.scaled(from: original.bounds, to: newBounds)

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
                windowTargets = []
                startEditing()
            } else {
                self.selection = nil
                if let hovered = windowUnderMouse(point) {
                    let targets = windowTargets.contains(where: { $0.id == hovered.id })
                        ? windowTargets
                        : [CaptureWindowTarget(id: hovered.id, rect: hovered.rect)]
                    applyWindowTargets(targets, startEditing: true)
                } else if windowTargets.isEmpty {
                    onCancel?()
                } else {
                    windowTargets = []
                    needsDisplay = true
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

        case .movingAnnotation, .resizingAnnotation:
            session.endInteractiveChange()

        case .resizing:
            loadBase()

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
                style: session.defaultStyle
            )
        case .text, .number:
            break
        default:
            draft = Annotation(
                shape: draftShape(from: start, to: current),
                style: session.defaultStyle
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
        session.recordUndoSnapshot()
        session.annotations.append(Annotation(shape: shape, style: session.defaultStyle))
    }

    // MARK: - Text entry

    private func showTextField(at point: CGPoint) {
        removeTextField()
        textAnchor = point

        let field = NSTextField(frame: NSRect(x: point.x, y: point.y - 12, width: 200, height: 24))
        field.placeholderString = t("Text")
        field.font = .systemFont(ofSize: 13)
        field.target = self
        field.action = #selector(commitText)
        field.delegate = self
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    @objc private func commitText() {
        commitTextFieldIfNeeded()
    }

    /// Commits a pending text annotation; an empty field just disappears. Also
    /// called when the field loses focus, so a stray click never leaves a box
    /// hanging around.
    private func commitTextFieldIfNeeded() {
        guard let field = textField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        removeTextField()
        if !text.isEmpty, let selection {
            commit(.text(text, at: normalize(textAnchor, in: selection)))
        }
        needsDisplay = true
    }

    private func removeTextField() {
        guard let field = textField else { return }
        textField = nil
        field.delegate = nil
        field.removeFromSuperview()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if editing {
            if let command = Self.historyCommand(for: event) {
                performHistory(command)
                return
            }

            switch event.keyCode {
            case 53: onCancel?()                                  // Esc
            case 36, 76: finish(.copy)                            // Return
            case 49: finish(.save)                                // Space
            case 35: finish(.pin)                                 // P
            default: break
            }
            return
        }

        switch event.keyCode {
        case 53:
            if !windowTargets.isEmpty {
                windowTargets = []
                selection = nil
                needsDisplay = true
            } else if selection != nil {
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
            windowTargets = []
            selection = bounds
            startEditing()
        case 15:
            if let last = SelectionMemory.lastSelection {
                windowTargets = []
                selection = clamp(last.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY))
                needsDisplay = true
            }
        default:
            break
        }
    }

    /// Shared by the local key monitor and `keyDown` so both entry points treat
    /// ⌘Z and ⇧⌘Z the same way.
    static func historyCommand(for event: NSEvent) -> HistoryCommand? {
        guard event.keyCode == 6, event.modifierFlags.contains(.command) else { return nil }
        return event.modifierFlags.contains(.shift) ? .redo : .undo
    }

    private func performHistory(_ command: HistoryCommand) {
        switch command {
        case .undo:
            guard session.canUndo else { return }
        case .redo:
            guard session.canRedo else { return }
        }
        cancelCanvasInteractionForHistory()
        switch command {
        case .undo: session.undo()
        case .redo: session.redo()
        }
        needsDisplay = true
    }

    /// Undo and redo must end an annotation drag or drawing preview that is
    /// under way; otherwise its cached `original`/`index` would be written over
    /// the restored content by the next `mouseDragged`. Selection geometry is
    /// not part of history, so its drag keeps running to its usual `mouseUp`.
    private func cancelCanvasInteractionForHistory() {
        switch interaction {
        case .movingAnnotation, .resizingAnnotation:
            interaction = .none
            session.endInteractiveChange()
        case .drawing:
            interaction = .none
            draft = nil
            penPoints = []
            startPoint = nil
        case .none, .creating, .moving, .resizing:
            break
        }
    }

    // MARK: - Geometry

    private func beginSelectionInteraction(at point: CGPoint, in selection: CGRect) {
        let normalized = normalize(point, in: selection)

        if let index = session.selectionIndex, session.annotations.indices.contains(index) {
            let rect = viewRect(for: session.annotations[index].bounds, in: selection)
            if let handle = handle(at: point, in: rect) {
                session.beginInteractiveChange()
                interaction = .resizingAnnotation(
                    handle: handle,
                    index: index,
                    original: session.annotations[index],
                    rect: rect
                )
                return
            }
        }

        if let index = annotationIndex(at: normalized) {
            session.selectionIndex = index
            session.beginInteractiveChange()
            interaction = .movingAnnotation(
                start: normalized,
                index: index,
                original: session.annotations[index]
            )
            needsDisplay = true
            return
        }

        session.selectionIndex = nil
        needsDisplay = true
    }

    private func annotationIndex(at point: CGPoint) -> Int? {
        for index in session.annotations.indices.reversed() where session.annotations[index].contains(point) {
            return index
        }
        return nil
    }

    private func viewRect(for bounds: CGRect, in selection: CGRect) -> CGRect {
        CGRect(
            x: selection.minX + bounds.minX * selection.width,
            y: selection.maxY - bounds.maxY * selection.height,
            width: bounds.width * selection.width,
            height: bounds.height * selection.height
        )
    }

    private func normalizedRect(_ rect: CGRect, in selection: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - selection.minX) / max(1, selection.width),
            y: (selection.maxY - rect.maxY) / max(1, selection.height),
            width: rect.width / max(1, selection.width),
            height: rect.height / max(1, selection.height)
        )
    }

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
        guard !editing, interaction.isIdle else { return }
        guard selection == nil || !windowTargets.isEmpty else { return }
        hovered = windowUnderMouse(point)
        needsDisplay = true
    }

    /// Picks the window under the pointer into the pending set, or removes it.
    private func toggleWindowTarget(_ hovered: (id: CGWindowID, rect: CGRect)) {
        var targets = windowTargets
        if let index = targets.firstIndex(where: { $0.id == hovered.id }) {
            targets.remove(at: index)
        } else {
            targets.append(CaptureWindowTarget(id: hovered.id, rect: hovered.rect))
        }
        applyWindowTargets(targets, startEditing: false)
    }

    private func applyWindowTargets(_ targets: [CaptureWindowTarget], startEditing shouldEdit: Bool) {
        windowTargets = targets
        guard let canvas = WindowComposer.canvas(for: targets, screenBounds: bounds) else {
            windowTargets = []
            selection = nil
            needsDisplay = true
            return
        }
        selection = canvas
        if shouldEdit {
            startEditing()
        } else {
            needsDisplay = true
        }
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

        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let excluded = SelectionController.overlayWindowIDs

        for info in list {
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  !excluded.contains(id),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer >= NSWindow.Level.normal.rawValue,
                  layer <= NSWindow.Level.modalPanel.rawValue,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { continue }
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
            return (id, local)
        }
        return nil
    }
}

/// Remembers the last region so `R` can reuse it.
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

extension SelectionView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextFieldIfNeeded()
    }
}

/// Small non-activating toast used when a colour is copied.
@MainActor
enum ColorToast {
    private static var windows: [NSWindow] = []

    static func show(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let padding: CGFloat = 14
        let size = NSSize(
            width: label.frame.width + padding * 2,
            height: label.frame.height + padding
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.95).cgColor
        container.layer?.cornerRadius = 8
        label.frame.origin = NSPoint(x: padding, y: padding / 2)
        container.addSubview(label)
        window.contentView = container

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var origin = NSPoint(x: mouse.x + 18, y: mouse.y - size.height - 18)
        origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
        origin.y = min(max(visible.minY + 8, origin.y), visible.maxY - size.height - 8)
        window.setFrameOrigin(origin)

        window.orderFrontRegardless()
        windows.append(window)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            window.orderOut(nil)
            windows.removeAll { $0 === window }
        }
    }
}
