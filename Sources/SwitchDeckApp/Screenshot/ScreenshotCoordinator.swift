import AppKit
import ImageIO
import SwitchKit
import UniformTypeIdentifiers

/// Owns the screenshot flow: in-place selection and editing, then capture,
/// compose and deliver (copy, save or pin).
@MainActor
final class ScreenshotCoordinator {
    private let selections = SelectionController()
    private let capture = ScreenCaptureService()
    private var pinnedWindows: [NSWindow] = []
    private var countdown: CaptureCountdown?
    /// Frames taken just before a timed overlay appeared, keyed by display.
    private var frozenScreens: [CGDirectDisplayID: CGImage] = [:]
    private let recognitionWindow = TextRecognitionWindowController()

    /// The catalog id, also used for the shortcut the settings pane edits.
    static let id = "screenshot"

    var switchItem: SwitchItem {
        SwitchItem(
            id: Self.id,
            title: t("Screenshot"),
            symbolName: "camera.viewfinder",
            kind: .action,
            perform: { [weak self] in self?.begin() }
        )
    }

    /// The text-recognition switch: same overlay, no editor.
    static let recognizeTextID = "recognizeText"

    var recognizeTextItem: SwitchItem {
        SwitchItem(
            id: Self.recognizeTextID,
            title: t("Recognize Text"),
            symbolName: "text.viewfinder",
            kind: .action,
            perform: { [weak self] in self?.beginTextRecognition() }
        )
    }

    /// Select a region or window, then read its text. There is no delay and
    /// no editor: choosing the area is the whole interaction.
    func beginTextRecognition() {
        guard !selections.isActive, countdown == nil else { return }
        // Load the models while the user is still selecting.
        Task.detached(priority: .userInitiated) { TextRecognizer.warmUp() }
        start(initialSelection: nil, finishOnSelect: .recognizeText)
    }

    /// Debug (`--ocr-demo`): recognition over `$SWITCHDECK_DEMO_IMAGE`, so the
    /// result window and the silent toast can be checked without selecting.
    func beginRecognitionDemo() {
        guard let path = ProcessInfo.processInfo.environment["SWITCHDECK_DEMO_IMAGE"],
              let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            print("--ocr-demo needs SWITCHDECK_DEMO_IMAGE")
            return
        }
        Task { @MainActor in await recognizeText(in: image) }
    }

    /// Read-only state for tests: the capture overlay is open.
    var isSelectionActive: Bool { selections.isActive }

    deinit {
        pinnedWindows.removeAll()
    }

    func begin() {
        guard !selections.isActive else { return }

        // A second press while the clock runs calls the capture off.
        if let countdown {
            countdown.cancel()
            self.countdown = nil
            return
        }

        let seconds = ScreenshotPreferences.delaySeconds
        guard seconds > 0 else {
            start(initialSelection: nil)
            return
        }

        let hud = CaptureCountdown(seconds: seconds)
        countdown = hud
        hud.start { [weak self] in
            guard let self else { return }
            self.countdown = nil
            Task { @MainActor in
                let frozen = await self.captureEveryScreen()
                self.start(initialSelection: nil, frozen: frozen)
            }
        }
    }

    /// Debug: runs the real delayed path with a 3 second clock, so the pill and
    /// the frozen frame can be checked without pressing the shortcut.
    func beginTimedDemo() {
        let stored = UserDefaults.standard.object(forKey: ScreenshotPreferences.delayKey)
        UserDefaults.standard.set(3, forKey: ScreenshotPreferences.delayKey)
        begin()
        if let stored {
            UserDefaults.standard.set(stored, forKey: ScreenshotPreferences.delayKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ScreenshotPreferences.delayKey)
        }
    }

    /// Debug: opens the overlay with a region already in edit mode, so the
    /// toolbar layout can be checked without dragging.
    func beginDemo() {
        start(initialSelection: CGRect(x: 300, y: 240, width: 900, height: 520))
    }

    /// Debug (`--editor-demo`): the editor over a still image instead of the
    /// live desktop, so a README or a bug report never shows what is on screen.
    /// The image comes from `SWITCHDECK_DEMO_IMAGE`; without it the demo falls
    /// back to the frozen desktop, like `--selection-demo`.
    func beginEditorDemo() {
        var frozen: [CGDirectDisplayID: CGImage] = [:]
        if let path = ProcessInfo.processInfo.environment["SWITCHDECK_DEMO_IMAGE"],
           let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            for screen in NSScreen.screens {
                if let id = Self.displayID(for: screen) { frozen[id] = image }
            }
        }

        start(
            initialSelection: CGRect(x: 360, y: 200, width: 1000, height: 600),
            frozen: frozen
        )

        guard !frozen.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.selections.session.annotations = [
                Annotation(
                    shape: .rectangle(from: CGPoint(x: 0.09, y: 0.14), to: CGPoint(x: 0.54, y: 0.47)),
                    color: .red,
                    lineWidth: 0.005
                ),
                Annotation(
                    shape: .arrow(from: CGPoint(x: 0.60, y: 0.63), to: CGPoint(x: 0.87, y: 0.28)),
                    color: .red,
                    lineWidth: 0.005
                ),
                Annotation(
                    shape: .text("SwitchDeck", at: CGPoint(x: 0.10, y: 0.66)),
                    color: .red,
                    textScale: 0.045
                ),
            ]
        }
    }

    /// Debug: scrolling capture over a region of the main screen. Blocked
    /// while scrolling capture is unavailable, before any overlay or timer.
    func beginScrollingDemo() {
        guard ScreenshotAvailability.scrollingCapture else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let rect = CGRect(
            x: screen.frame.midX - 350,
            y: screen.frame.midY - 210,
            width: 700,
            height: 420
        )
        start(initialSelection: rect)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.selections.startScrollingForDebug()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            self?.selections.stopScrollingForDebug()
        }
    }

    /// Debug: demo plus a tiled, rotated watermark.
    func beginWatermarkDemo() {
        beginDemo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.selections.session.watermarkEnabled = true
            self.selections.session.watermarkPlacement = .tiled
            self.selections.session.watermarkRotation = -30
            self.selections.session.watermarkOpacity = 0.25
        }
    }

    /// Debug: demo selection, saved straight to the configured folder.
    func beginDemoSave() {
        beginDemo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.selections.completeForDebug(.save)
        }
    }

    /// Debug: compares a normal capture with one that excludes capture UI while
    /// the overlay is up, to prove the overlay is not baked into the image.
    func compareCaptures() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        guard let displayID = Self.displayID(for: screen) else { return }

        Task {
            let plain = try? await capture.captureDisplay(displayID: displayID)
            let excluded = try? await capture.captureDisplay(
                displayID: displayID, excludingWindowIDs: SelectionController.overlayWindowIDs
            )

            for (name, image) in [("plain", plain), ("excluded", excluded)] {
                guard let image else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                let data = rep.representation(using: .png, properties: [:])
                try? data?.write(to: URL(fileURLWithPath: "/tmp/sd-capture-\(name).png"))
            }
        }
    }

    /// Debug: demo selection, then copy it after a moment. Verifies the whole
    /// capture → compose → clipboard path without any clicking.
    func beginDemoCopy() {
        beginDemo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            let mosaic = Annotation(
                shape: .mosaic(from: CGPoint(x: 0.1, y: 0.2), to: CGPoint(x: 0.45, y: 0.7)),
                color: .red
            )
            let blur = Annotation(
                shape: .blur(from: CGPoint(x: 0.55, y: 0.2), to: CGPoint(x: 0.9, y: 0.5)),
                color: .red
            )
            self?.selections.completeForDebug(.copy, extraAnnotations: [mosaic, blur])
        }
    }

    private func start(
        initialSelection: CGRect?,
        frozen: [CGDirectDisplayID: CGImage] = [:],
        finishOnSelect: CaptureSession.Output? = nil
    ) {
        guard !selections.isActive else { return }

        frozenScreens = frozen
        selections.session.prepareForCapture()

        selections.begin(
            onCapture: { [weak self] payload, output in
                Task { @MainActor in
                    await self?.finish(payload, output)
                }
            },
            onCancel: { [weak self] in
                self?.frozenScreens.removeAll()
            },
            captureBase: { [weak self] rect, screen in
                await self?.captureRegion(rect, screen)
            },
            captureWindows: { [weak self] targets, canvas, screen in
                await self?.captureWindows(targets, canvas: canvas, screen: screen)
            },
            initialSelection: initialSelection,
            frozen: { [weak self] screen in
                guard let self, let id = Self.displayID(for: screen) else { return nil }
                return self.frozenScreens[id]
            },
            finishOnSelect: finishOnSelect,
            captureLive: { [weak self] rect, screen in
                await self?.captureLiveRegion(rect, screen)
            }
        )
    }

    /// One frame per display, taken while the desktop is still untouched.
    private func captureEveryScreen() async -> [CGDirectDisplayID: CGImage] {
        var frames: [CGDirectDisplayID: CGImage] = [:]
        for screen in NSScreen.screens {
            guard let id = Self.displayID(for: screen),
                  let image = try? await capture.captureDisplay(
                    displayID: id, excludingWindowIDs: SelectionController.overlayWindowIDs
                  )
            else { continue }
            frames[id] = image
        }
        return frames
    }

    /// Always reads the live screen, ignoring any frozen frame.
    private func captureLiveRegion(_ rect: CGRect, _ screen: NSScreen) async -> CGImage? {
        guard let displayID = Self.displayID(for: screen) else { return nil }
        return try? await capture.captureRegion(
            displayID: displayID,
            rect: rect,
            screenFrame: screen.frame,
            excludingWindowIDs: SelectionController.overlayWindowIDs
        )
    }

    private func captureRegion(_ rect: CGRect, _ screen: NSScreen) async -> CGImage? {
        guard let displayID = Self.displayID(for: screen) else { return nil }

        if let frozen = frozenScreens[displayID] {
            return ScreenCaptureService.crop(image: frozen, to: rect, screenFrame: screen.frame)
        }

        return try? await capture.captureRegion(
            displayID: displayID,
            rect: rect,
            screenFrame: screen.frame,
            excludingWindowIDs: SelectionController.overlayWindowIDs
        )
    }

    /// Captures each picked window on its own, then lays them out at their
    /// on-screen positions. If any picked window vanishes, keep the selection
    /// failed rather than silently dropping a window or capturing the desktop.
    private func captureWindows(
        _ targets: [CaptureWindowTarget],
        canvas: CGRect,
        screen: NSScreen
    ) async -> CGImage? {
        guard !targets.isEmpty else { return nil }

        var shots: [(image: CGImage, rect: CGRect)] = []
        for target in targets {
            guard let image = try? await capture.captureWindow(windowID: target.id) else { return nil }
            shots.append((image, target.rect))
        }
        guard !shots.isEmpty else { return nil }

        return WindowComposer.compose(
            shots: shots,
            canvas: canvas,
            scale: screen.backingScaleFactor
        )
    }

    // MARK: - Finish

    private func finish(_ payload: CapturePayload, _ output: CaptureSession.Output) async {
        defer { frozenScreens.removeAll() }
        do {
            // The overlay already froze the region for live mosaic/blur; only
            // capture again if that never arrived.
            let cropped: CGImage
            if let base = payload.base {
                cropped = base
            } else if let region = await captureRegion(payload.rect, payload.screen) {
                cropped = region
            } else {
                throw ScreenCaptureService.CaptureError.captureFailed(t("The selected area was empty."))
            }

            if output == .recognizeText {
                await recognizeText(in: cropped)
                return
            }

            let visibleWatermark = payload.watermarkVisible ? payload.watermark : nil
            let image = AnnotationRenderer.render(
                base: cropped,
                annotations: payload.annotations,
                watermark: visibleWatermark
            )

            switch output {
            case .copy:
                copy(image)
            case .save:
                save(image, watermark: payload.watermark)
            case .pin:
                pin(image)
            case .recognizeText:
                break
            }
        } catch {
            present(error)
        }
    }

    private func recognizeText(in image: CGImage) async {
        let result: TextRecognizer.Result
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try TextRecognizer.recognize(image)
            }.value
        } catch {
            present(error, title: t("Recognize Text"))
            return
        }

        let preview = NSImage(cgImage: image, size: .zero)
        guard ScreenshotPreferences.silentRecognition else {
            recognitionWindow.show(image: preview, result: result)
            return
        }

        guard let text = result.clipboardText else {
            RecognitionToast.show(t("No text found"), detail: nil) { [weak self] in
                self?.recognitionWindow.show(image: preview, result: result)
            }
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        RecognitionToast.show(
            result.foundCode ? t("Copied QR code") : t("Copied text"),
            detail: RecognitionToast.preview(of: text)
        ) { [weak self] in
            self?.recognitionWindow.show(image: preview, result: result)
        }
    }

    private func copy(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func save(_ image: NSImage, watermark: AnnotationRenderer.WatermarkOptions?) {
        guard ScreenshotSaver.save(image, watermark: watermark) != nil else {
            let folder = (ScreenshotPreferences.folder.path as NSString).abbreviatingWithTildeInPath
            present(
                ScreenCaptureService.CaptureError.captureFailed(
                    "The screenshot could not be written to \(folder)."
                )
            )
            return
        }
    }

    private func pin(_ image: NSImage) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maxWidth = screen.visibleFrame.width * 0.55
        let scale = min(1, maxWidth / max(1, image.size.width))
        let size = NSSize(
            width: max(80, image.size.width * scale),
            height: max(60, image.size.height * scale)
        )

        let window = PinnedWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let content = PinnedContentView(frame: NSRect(origin: .zero, size: size))
        content.imageView.image = image
        content.onClose = { [weak window] in window?.close() }
        window.contentView = content

        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2
        )
        window.setFrameTopLeftPoint(NSPoint(x: origin.x, y: origin.y + size.height))
        window.makeKeyAndOrderFront(nil)

        pinnedWindows.append(window)
    }

    private func present(_ error: Error, title: String = t("Screenshot")) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: t("OK"))

        if case ScreenCaptureService.CaptureError.permission = error {
            alert.addButton(withTitle: t("Open Privacy Settings"))
            if alert.runModal() == .alertSecondButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                NSWorkspace.shared.open(url)
            }
            return
        }

        alert.runModal()
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }
}

/// Floating pill that counts down before a timed capture. It never takes key
/// focus or clicks, so whatever the user is setting up underneath keeps going.
@MainActor
final class CaptureCountdown {
    private let totalSeconds: Int
    private var panel: NSPanel?
    private var label: NSTextField?
    private var task: Task<Void, Never>?

    init(seconds: Int) {
        totalSeconds = seconds
    }

    func start(onFinish: @escaping () -> Void) {
        show()

        task = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: self.totalSeconds, through: 1, by: -1) {
                if Task.isCancelled {
                    self.close()
                    return
                }
                self.update(remaining)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if Task.isCancelled {
                self.close()
                return
            }
            self.close()
            onFinish()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        close()
    }

    private func show() {
        let size = NSSize(width: 190, height: 54)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        content.layer?.cornerRadius = 14
        content.layer?.cornerCurve = .continuous

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 12, y: (size.height - 22) / 2, width: size.width - 24, height: 22)
        content.addSubview(label)

        panel.contentView = content

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height - 56
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.label = label
    }

    private func update(_ seconds: Int) {
        label?.stringValue = tf("Screenshot in %d…", seconds)
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
        label = nil
    }
}

/// A pinned screenshot: scroll resizes it, ⌘-scroll changes opacity, Esc or the
/// corner button closes it.
private final class PinnedWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let contentView else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: t("Copy"), action: #selector(copyImage), keyEquivalent: "c").target = self
        menu.addItem(withTitle: t("50% Opacity"), action: #selector(toggleHalfOpacity), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: t("Close"), action: #selector(closeSelf), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
    }

    @objc private func closeSelf() {
        close()
    }

    @objc private func copyImage() {
        guard let view = contentView as? PinnedContentView, let image = view.imageView.image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    @objc private func toggleHalfOpacity() {
        alphaValue = alphaValue < 0.99 ? 1 : 0.5
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY

        if event.modifierFlags.contains(.command) {
            alphaValue = min(1, max(0.2, alphaValue - delta * 0.015))
            return
        }

        let factor = 1 + delta * 0.01
        var frame = self.frame
        let width = min(max(80, frame.width * factor), 4000)
        let height = min(max(60, frame.height * factor), 4000)

        frame.origin.x -= (width - frame.width) / 2
        frame.origin.y -= (height - frame.height) / 2
        frame.size = NSSize(width: width, height: height)
        setFrame(frame, display: true)
        contentView?.frame = NSRect(origin: .zero, size: frame.size)
    }
}

/// Image plus a close button that fades up when the pointer is over the pin.
private final class PinnedContentView: NSView {
    let imageView = NSImageView()
    var onClose: (() -> Void)?

    private let closeButton = NSButton()
    private var hoverTracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)

        closeButton.isBordered = false
        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.contentTintColor = .white
        closeButton.alphaValue = 0.5
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) {
        fatalError("PinnedContentView is created in code only")
    }

    override func layout() {
        super.layout()
        let size: CGFloat = 20
        closeButton.frame = NSRect(
            x: bounds.maxX - size - 6,
            y: bounds.maxY - size - 6,
            width: size,
            height: size
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking {
            removeTrackingArea(hoverTracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.alphaValue = 1
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.alphaValue = 0.5
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
