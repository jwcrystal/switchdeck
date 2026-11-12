import AppKit
import SwitchKit

/// The app is a menu-bar accessory: no Dock icon, no main menu.
@main
enum SwitchDeckApp {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments

        if arguments.contains("--dump") {
            Dump.printAll()
            return
        }

        if let index = arguments.firstIndex(of: "--run"), arguments.count > index + 1 {
            Dump.run(id: arguments[index + 1])
            return
        }

        if arguments.contains("--hotkeys") {
            Dump.checkHotkeys()
            return
        }

        if arguments.contains("--menu") {
            Dump.printMenu()
            return
        }

        if arguments.contains("--permissions") {
            Dump.printPermissions()
            return
        }

        if arguments.contains("--probe-automation") {
            Dump.probeAutomation()
            return
        }

        if arguments.contains("--capture-test") {
            Dump.captureTest()
            return
        }

        if arguments.contains("--window-check") {
            Dump.windowCheck()
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

/// Prints every switch with its current state. Used by `scripts/smoke.sh` and
/// helpful when a switch misbehaves: `build/SwitchDeck.app/Contents/MacOS/SwitchDeck --dump`.
enum Dump {
    @MainActor
    static func printAll() {
        for item in AppCatalog.make(screenshot: ScreenshotCoordinator()).items {
            print(line(for: item))
        }
    }

    /// Runs one switch without opening the menu: `--run keepAwake`.
    /// Toggles flip state, so the printed state afterwards shows the result.
    @MainActor
    static func run(id: String) {
        guard let item = AppCatalog.make(screenshot: ScreenshotCoordinator()).item(id: id) else {
            FileHandle.standardError.write(Data("Unknown switch: \(id)\n".utf8))
            exit(2)
        }
        do {
            try item.perform()
        } catch {
            FileHandle.standardError.write(Data("\(item.title) failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        print(line(for: item))
    }

    private static func line(for item: SwitchItem) -> String {
        let state: String
        switch item.kind {
        case .toggle: state = item.state() ? "on" : "off"
        case .action: state = "-"
        }
        let subtitle = item.subtitle().map { " (\($0))" } ?? ""
        return "\(item.id)\t\(item.title)\t\(state)\(subtitle)"
    }

    /// Prints the menu exactly as the status item builds it, including hidden
    /// switches being absent. Useful when the menu looks wrong.
    @MainActor
    static func printMenu() {
        let model = AppModel()
        var seen = Set<String>()
        let items = model.menuItems.filter { seen.insert($0.id).inserted }

        print("menu items: \(items.count) (of \(model.catalog.items.count) switches, \(model.config.disabled.count) hidden)")
        for (index, item) in items.enumerated() {
            var parts = [item.title]
            if let subtitle = item.subtitle() { parts.append("(\(subtitle))") }
            let shortcut = model.config.hotkey(for: item.id)?.displayString
            if let shortcut { parts.append("[\(shortcut)]") }
            print(String(format: "%2d", index + 1), parts.joined(separator: " "))
        }
    }

    /// Prints the permission state the app itself sees. Also writes
    /// `/tmp/switchdeck-permissions.txt` for a GUI launch.
    @MainActor
    static func printPermissions() {
        let center = PermissionCenter()
        center.refresh()

        func label(_ state: PermissionCenter.AutomationState) -> String {
            switch state {
            case .granted: return "granted"
            case .denied: return "missing"
            case .unknown: return "unknown"
            }
        }

        var lines = [
            "accessibility\t\(center.accessibility ? "granted" : "missing")",
            "automation:systemEvents\t\(label(center.systemEvents))",
            "automation:finder\t\(label(center.finder))",
        ]

        switch center.microphone {
        case .authorized: lines.append("microphone\tgranted")
        case .notDetermined: lines.append("microphone\tnot asked")
        case .denied: lines.append("microphone\tmissing")
        case .restricted: lines.append("microphone\trestricted")
        @unknown default: lines.append("microphone\tunknown")
        }
        lines.append("allGranted\t\(center.allGranted)")

        for line in lines { print(line) }
        try? lines.joined(separator: "\n").write(
            to: URL(fileURLWithPath: "/tmp/switchdeck-permissions.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Sends one harmless event per target, the same call the Grant button
    /// makes, and prints what macOS answered. Also writes the same lines to
    /// `/tmp/switchdeck-probe.txt`, because a GUI launch has no stdout.
    @MainActor
    static func probeAutomation() {
        let targets = [
            ("System Events", #"tell application "System Events" to get name"#),
            ("Finder", #"tell application "Finder" to get name of startup disk"#),
        ]

        var lines: [String] = []
        for (name, script) in targets {
            do {
                let result = try Automation.run(script)
                lines.append("\(name)\tok\t\(result.stringValue ?? "")")
            } catch {
                lines.append("\(name)\tfailed\t\(error.localizedDescription)")
            }
        }

        for line in lines {
            print(line)
        }
        try? lines.joined(separator: "\n").write(
            to: URL(fileURLWithPath: "/tmp/switchdeck-probe.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Captures the main display to /tmp and writes the outcome next to it.
    /// Verifies ScreenCaptureKit and the Screen Recording grant without any UI.
    @MainActor
    static func captureTest() {
        let service = ScreenCaptureService()
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let displayID = (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? CGMainDisplayID()

        func write(_ text: String) {
            print(text)
            try? text.write(
                to: URL(fileURLWithPath: "/tmp/switchdeck-capture.txt"),
                atomically: true,
                encoding: .utf8
            )
        }

        Task {
            do {
                let image = try await service.captureDisplay(displayID: displayID)
                let rep = NSBitmapImageRep(cgImage: image)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try data.write(to: URL(fileURLWithPath: "/tmp/switchdeck-capture.png"))
                }
                write("ok \(image.width)x\(image.height)")
            } catch {
                write("failed \(error.localizedDescription)")
            }
            exit(0)
        }

        RunLoop.main.run()
    }

    /// Prints which normal window sits under the mouse, using the same
    /// coordinate conversion as the selection overlay.
    @MainActor
    static func windowCheck() {
        let mouse = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else {
            print("no primary screen")
            return
        }
        let topLeft = CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)
        print("mouse=\(mouse) cg=\(topLeft)")

        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID else { continue }
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { continue }
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict)
            else { continue }
            guard rect.contains(topLeft) else { continue }

            let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
            let id = info[kCGWindowNumber as String] ?? "?"
            print("hit owner=\(owner) id=\(id) pid=\(pid) bounds=\(rect)")
            return
        }
        print("no window at cursor")
    }

    /// Registers a probe shortcut through the real Carbon path and reports the
    /// result. Uses a throwaway config file so the user's shortcuts stay alone.
    @MainActor
    static func checkHotkeys() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("switchdeck-hotkey-check.json")
        try? FileManager.default.removeItem(at: url)

        let store = ConfigStore(url: url)
        store.update { config in
            config.setHotkey(
                HotkeyBinding(
                    keyCode: 40, // K
                    modifiers: HotkeyBinding.controlModifier | HotkeyBinding.optionModifier,
                    label: "K"
                ),
                for: "keepAwake"
            )
        }

        let model = AppModel(store: store)
        let binding = model.config.hotkey(for: "keepAwake")?.displayString ?? "none"
        print("registered\t\(binding)")
        if model.hotkeyIssues.isEmpty {
            print("issues\tnone")
        } else {
            for issue in model.hotkeyIssues {
                print("issue\t\(issue)")
            }
        }
        try? FileManager.default.removeItem(at: url)
    }
}
