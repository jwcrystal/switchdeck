import AppKit
import SwiftUI
import SwitchKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let screenshot = ScreenshotCoordinator()
    private lazy var model: AppModel = {
        AppModel(catalog: AppCatalog.make(screenshot: screenshot))
    }()
    private let permissions = PermissionCenter()
    private var menuController: MenuController?
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var demoEditor: ScreenshotEditorController?
    private var instanceLockFD: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One menu-bar icon per user: a second instance would add a duplicate
        // status item with an identical menu. The flock also covers a race
        // between two launches started at the same moment.
        guard acquireInstanceLock() else {
            NSApp.terminate(nil)
            return
        }

        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let other = others.first {
                other.activate()
                NSApp.terminate(nil)
                return
            }
        }

        let controller = MenuController(model: model)
        controller.openSettings = { [weak self] in self?.showSettings() }
        controller.openPermissions = { [weak self] in self?.showSetup() }
        menuController = controller

        permissions.refresh()
        let launchingForScreenshot = CommandLine.arguments.contains("--show-settings")
        if !model.config.didCompleteSetup && !launchingForScreenshot {
            showSetup()
        }

        if launchingForScreenshot {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showSettings()
            }
        }

        if CommandLine.arguments.contains("--editor-demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.showEditorDemo()
            }
        }

        if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak controller] in
                controller?.openMenuForDebug()
            }
        }
    }

    /// `--editor-demo` opens the editor with a drawn image, so the layout can be
    /// checked without Screen Recording permission.
    private func showEditorDemo() {
        let size = NSSize(width: 1200, height: 700)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 230, height: size.height).fill()

        NSColor(calibratedWhite: 0.86, alpha: 1).setFill()
        for (index, width) in [260.0, 420.0, 380.0, 440.0].enumerated() {
            let rect = NSRect(x: 300, y: 560 - Double(index) * 34, width: width, height: 12)
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }

        NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 300, y: 300, width: 200, height: 64),
            xRadius: 10,
            yRadius: 10
        ).fill()

        image.unlockFocus()

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let controller = ScreenshotEditorController(image: cgImage) { [weak self] in
            self?.demoEditor = nil
        }
        demoEditor = controller
        controller.show()
    }

    /// The single place the app asks for permissions: shown at launch while
    /// something is missing, and reachable later from the menu.
    func showSetup() {
        if let window = setupWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SetupView(permissions: permissions) { [weak self] in
            self?.model.markSetupComplete()
            self?.setupWindow?.close()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Set up SwitchDeck"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        setupWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// `--pane customize` opens Settings on a given page; used for screenshots
    /// and quick checks.
    private func paneArgument() -> SettingsView.Pane {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--pane"), arguments.indices.contains(index + 1) else {
            return .general
        }
        return SettingsView.Pane(rawValue: arguments[index + 1]) ?? .general
    }

    private func acquireInstanceLock() -> Bool {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwitchDeck")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let fd = open(support.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        instanceLockFD = fd
        return true
    }

    func showSettings() {
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(
            model: model,
            permissions: permissions,
            initialPane: paneArgument()
        ))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SwitchDeck"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
