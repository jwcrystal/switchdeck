import AppKit
import SwitchKit
import UniformTypeIdentifiers

/// Owns the screenshot flow: in-place selection and editing, then capture,
/// compose and deliver (copy, save or pin).
@MainActor
final class ScreenshotCoordinator {
    private let selections = SelectionController()
    private let capture = ScreenCaptureService()
    private var pinnedWindows: [NSWindow] = []

    var switchItem: SwitchItem {
        SwitchItem(
            id: "screenshot",
            title: "Screenshot",
            symbolName: "camera.viewfinder",
            kind: .action,
            perform: { [weak self] in self?.begin() }
        )
    }

    deinit {
        pinnedWindows.removeAll()
    }

    func begin() {
        start(initialSelection: nil)
    }

    /// Debug: opens the overlay with a region already in edit mode, so the
    /// toolbar layout can be checked without dragging.
    func beginDemo() {
        start(initialSelection: CGRect(x: 300, y: 240, width: 900, height: 520))
    }

    /// Debug: demo selection, then copy it after a moment. Verifies the whole
    /// capture → compose → clipboard path without any clicking.
    func beginDemoCopy() {
        beginDemo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.selections.completeForDebug(.copy)
        }
    }

    private func start(initialSelection: CGRect?) {
        guard !selections.isActive else { return }

        selections.begin(
            onCapture: { [weak self] rect, screen, annotations, output in
                Task { @MainActor in
                    await self?.finish(rect: rect, screen: screen, annotations: annotations, output: output)
                }
            },
            onCancel: {},
            initialSelection: initialSelection
        )
    }

    // MARK: - Finish

    private func finish(
        rect: CGRect,
        screen: NSScreen,
        annotations: [Annotation],
        output: CaptureSession.Output
    ) async {
        do {
            guard let displayID = Self.displayID(for: screen) else {
                throw ScreenCaptureService.CaptureError.displayNotFound
            }

            let full = try await capture.captureDisplay(displayID: displayID, excludingOwnApp: true)
            guard let cropped = capture.crop(image: full, to: rect, screenFrame: screen.frame) else {
                throw ScreenCaptureService.CaptureError.captureFailed("The selected area was empty.")
            }

            let image = AnnotationRenderer.render(base: cropped, annotations: annotations)

            switch output {
            case .copy:
                copy(image)
            case .save:
                save(image)
            case .pin:
                pin(image)
            }
        } catch {
            present(error)
        }
    }

    private func copy(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func save(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Screenshot \(Self.stamp()).png"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else {
            present(ScreenCaptureService.CaptureError.captureFailed("The image could not be encoded as PNG."))
            return
        }

        do {
            try data.write(to: url)
        } catch {
            present(error)
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
        window.onClose = { [weak window] in window?.close() }

        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2
        )
        window.setFrameTopLeftPoint(NSPoint(x: origin.x, y: origin.y + size.height))
        window.makeKeyAndOrderFront(nil)

        pinnedWindows.append(window)
    }

    private func present(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screenshot"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")

        if case ScreenCaptureService.CaptureError.permission = error {
            alert.addButton(withTitle: "Open Privacy Settings")
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

/// A pinned screenshot: scroll resizes it, ⌘-scroll changes opacity, Esc or the
/// corner button closes it.
private final class PinnedWindow: NSWindow {
    var onClose: (() -> Void)?

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
        menu.addItem(withTitle: "Copy", action: #selector(copyImage), keyEquivalent: "c").target = self
        menu.addItem(withTitle: "50% Opacity", action: #selector(toggleHalfOpacity), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(closeSelf), keyEquivalent: "").target = self
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
