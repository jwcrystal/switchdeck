import AppKit
import SwiftUI
import SwitchKit

/// Owns the screenshot flow: selection overlay → capture → editor.
@MainActor
final class ScreenshotCoordinator {
    private let selections = SelectionController()
    private let capture = ScreenCaptureService()
    private var editorController: ScreenshotEditorController?

    var switchItem: SwitchItem {
        SwitchItem(
            id: "screenshot",
            title: "Screenshot",
            symbolName: "camera.viewfinder",
            kind: .action,
            perform: { [weak self] in self?.begin() }
        )
    }

    func begin() {
        guard !selections.isActive, editorController == nil else { return }

        selections.begin { [weak self] request in
            self?.handle(request)
        } onCancel: {}
    }

    private func handle(_ request: CaptureRequest) {
        Task {
            do {
                let image = try await capture(request)
                showEditor(with: image)
            } catch {
                present(error)
            }
        }
    }

    private func capture(_ request: CaptureRequest) async throws -> CGImage {
        switch request {
        case .window(let id):
            return try await capture.captureWindow(windowID: id)

        case .region(let rect, let screen):
            guard let displayID = Self.displayID(for: screen) else {
                throw ScreenCaptureService.CaptureError.displayNotFound
            }
            let full = try await capture.captureDisplay(displayID: displayID)
            guard let cropped = capture.crop(image: full, to: rect, screenFrame: screen.frame) else {
                throw ScreenCaptureService.CaptureError.captureFailed("The selected area was empty.")
            }
            return cropped
        }
    }

    private func showEditor(with image: CGImage) {
        let controller = ScreenshotEditorController(image: image) { [weak self] in
            self?.editorController = nil
        }
        editorController = controller
        controller.show()
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
}

/// Borderless panel that still accepts key events, so the editor can be focused
/// and dragged like HapiGo's floating screenshot window.
private final class EditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Hosts the SwiftUI editor in a normal window and releases the coordinator when
/// the window closes.
@MainActor
final class ScreenshotEditorController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model: EditorModel
    private let onClose: () -> Void

    init(image: CGImage, onClose: @escaping () -> Void) {
        self.model = EditorModel(image: image)
        self.onClose = onClose
        self.window = EditorWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.delegate = self

        let view = ScreenshotEditorView(model: model) { [weak self] in
            self?.window.close()
        }
        window.contentViewController = NSHostingController(rootView: view)

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maxWidth = screen.visibleFrame.width * 0.8
        let maxHeight = screen.visibleFrame.height * 0.8
        let scale = min(1, min(maxWidth / CGFloat(image.width), maxHeight / CGFloat(image.height)))
        let width = max(640, CGFloat(image.width) * scale + 20)
        let height = max(360, CGFloat(image.height) * scale + 72)
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
