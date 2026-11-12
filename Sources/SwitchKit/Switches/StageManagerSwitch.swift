import Foundation

/// Stage Manager and its "show recent apps" companion setting.
///
/// Both live in `com.apple.WindowManager`; the window manager only re-reads them
/// when it restarts, so a change is followed by `killall WindowManager` (which
/// launchd starts again immediately).
///
/// These key names are the ones macOS has used since Ventura. If a future build
/// renames them the switch still writes the value but nothing visibly happens —
/// check with `defaults read com.apple.WindowManager` if that occurs.
public final class StageManagerSwitch {
    private let domain = "com.apple.WindowManager"
    private let stageManagerKey = "GloballyEnabled"
    private let autohideKey = "AutoHide"

    public init() {}

    public var isOn: Bool { boolValue(for: stageManagerKey) }
    public var isAutohideOn: Bool { boolValue(for: autohideKey) }

    public func set(_ on: Bool) throws {
        try write(on, for: stageManagerKey)
    }

    public func setAutohide(_ on: Bool) throws {
        try write(on, for: autohideKey)
    }

    public func toggle() throws {
        try set(!isOn)
    }

    public func toggleAutohide() throws {
        try setAutohide(!isAutohideOn)
    }

    private func boolValue(for key: String) -> Bool {
        guard let result = try? Shell.run("/usr/bin/defaults", ["read", domain, key]) else {
            return false
        }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    private func write(_ on: Bool, for key: String) throws {
        let result = try Shell.run("/usr/bin/defaults", [
            "write", domain, key, "-bool", on ? "true" : "false",
        ])
        guard result.status == 0 else {
            throw SwitchDeckError.shell("Could not write \(domain) \(key): \(result.error)")
        }
        restartWindowManager()
    }

    private func restartWindowManager() {
        // Exits 1 when Stage Manager has never run in this session; harmless.
        _ = try? Shell.run("/usr/bin/killall", ["WindowManager"])
    }
}
