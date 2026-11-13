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

        if arguments.contains("--audio-inputs") {
            Dump.printAudioInputs()
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

        if arguments.contains("--window-capture-test") {
            Dump.windowCaptureTest()
            return
        }

        if arguments.contains("--scroll-test") {
            Dump.scrollTest()
            return
        }

        if arguments.contains("--region-bench") {
            Dump.regionBench()
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
        let model = AppModel(catalog: AppCatalog.make(screenshot: ScreenshotCoordinator()))
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

    /// Lists the microphones CoreAudio offers, marking the default. Used to
    /// check the Settings › Recording picker without opening the window.
    static func printAudioInputs() {
        let devices = AudioInput.devices()
        for device in devices {
            print("\(device.id)\t\(device.name)\(device.isDefault ? "\t(default)" : "")")
        }
        if devices.isEmpty { print("no input devices") }
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

    /// Debug: feeds two synthetic frames with a known 40 px scroll to the
    /// stitching matcher and prints what it detected.
    @MainActor
    static func scrollTest() {
        func frame(offset: Int) -> CGImage? {
            let width = 400, height = 300
            guard let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            // Top-left drawing so the offsets read like image rows.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)

            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(NSColor.darkGray.cgColor)
            for index in 0..<12 {
                let y = 80 + index * 18 + offset
                context.fill(CGRect(x: 20, y: y, width: 360, height: 7))
            }
            return context.makeImage()
        }

        guard let a = frame(offset: 0), let b = frame(offset: -40) else {
            print("failed to build frames")
            return
        }
        let shift = ScrollingCapture.detectShift(from: a, to: b)
        let height = ScrollingCapture.debugStitch([a, b])
        print("detected shift: \(shift) (expected 40, content moved up)")
        print("stitched height: \(height) (expected 340)")
    }

    /// Debug: times region captures, the frame source for scrolling capture.
    @MainActor
    static func regionBench() {
        let service = ScreenCaptureService()
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let displayID = (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        let rect = CGRect(
            x: screen.frame.midX - 300,
            y: screen.frame.midY - 200,
            width: 600,
            height: 400
        )

        Task {
            // First call warms the shareable-content cache; time the rest.
            _ = try? await service.captureRegion(
                displayID: displayID, rect: rect, screenFrame: screen.frame,
                excludingWindowIDs: SelectionController.overlayWindowIDs
            )

            var size = CGSize.zero
            var failures = 0
            let start = Date()
            for _ in 0..<10 {
                if let image = try? await service.captureRegion(
                    displayID: displayID, rect: rect, screenFrame: screen.frame,
                    excludingWindowIDs: SelectionController.overlayWindowIDs
                ) {
                    size = CGSize(width: image.width, height: image.height)
                } else {
                    failures += 1
                }
            }
            let ms = Date().timeIntervalSince(start) * 100
            print("region \(Int(rect.width))x\(Int(rect.height)) pts → \(Int(size.width))x\(Int(size.height)) px, \(String(format: "%.0f", ms)) ms/frame, \(failures) failures")
            exit(0)
        }

        RunLoop.main.run()
    }

    /// Prints which application window or panel sits under the mouse, using the same
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
        let excluded = SelectionController.overlayWindowIDs

        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  !excluded.contains(id),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer >= NSWindow.Level.normal.rawValue,
                  layer <= NSWindow.Level.modalPanel.rawValue,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { continue }
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict)
            else { continue }
            guard rect.width >= 60, rect.height >= 60, rect.contains(topLeft) else { continue }

            let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
            print("hit owner=\(owner) id=\(id) pid=\(pid) bounds=\(rect)")
            return
        }
        print("no window at cursor")
    }

    /// Captures the window under the pointer exactly as a click would, composes
    /// it with the editor shadow and writes /tmp/switchdeck-window.png and
    /// /tmp/switchdeck-composed.png.
    @MainActor
    static func windowCaptureTest() {
        let mouse = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
        else {
            print("no screen")
            return
        }

        let topLeft = CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let excluded = SelectionController.overlayWindowIDs

        guard let info = list.first(where: { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  !excluded.contains(id),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer >= NSWindow.Level.normal.rawValue,
                  layer <= NSWindow.Level.modalPanel.rawValue,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict)
            else { return false }
            return rect.width >= 60 && rect.height >= 60 && rect.contains(topLeft)
        }),
        let dict = info[kCGWindowBounds as String] as? NSDictionary,
        let rect = CGRect(dictionaryRepresentation: dict),
        let id = info[kCGWindowNumber as String] as? CGWindowID
        else {
            print("no window at cursor")
            return
        }

        let local = CGRect(
            x: rect.minX - screen.frame.minX,
            y: (primary.frame.height - rect.maxY) - screen.frame.minY,
            width: rect.width,
            height: rect.height
        )
        let target = CaptureWindowTarget(id: id, rect: local)
        guard let canvas = WindowComposer.canvas(
            for: [target],
            screenBounds: CGRect(origin: .zero, size: screen.frame.size)
        ) else {
            print("no canvas")
            return
        }

        Task {
            do {
                let image = try await ScreenCaptureService().captureWindow(windowID: id)
                let composed = WindowComposer.compose(
                    shots: [(image, local)],
                    canvas: canvas,
                    scale: screen.backingScaleFactor
                )

                for (name, cg) in [("window", image), ("composed", composed)] {
                    guard let cg else { continue }
                    let rep = NSBitmapImageRep(cgImage: cg)
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: URL(fileURLWithPath: "/tmp/switchdeck-\(name).png"))
                    }
                    print("\(name) \(cg.width)x\(cg.height)")
                }
                print("window id=\(id) local=\(local) canvas=\(canvas)")
            } catch {
                print("failed \(error.localizedDescription)")
            }
            exit(0)
        }

        RunLoop.main.run()
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
