import Foundation

/// "Automatically hide and show the Dock" in System Settings › Desktop & Dock.
///
/// The setting lives in `com.apple.dock` as `autohide`; a missing key means the
/// Dock is always visible. The Dock only re-reads its preferences when it
/// restarts, so a change is followed by `killall Dock` (which launchd starts
/// again immediately).
public protocol DockPreferences {
    /// False when the key is missing or unreadable.
    func autohide() -> Bool
    func setAutohide(_ on: Bool) throws
    func restartDock()
}

/// The real preferences: `defaults` for the value, `killall` for the restart.
public struct ShellDockPreferences: DockPreferences {
    private let domain = "com.apple.dock"
    private let key = "autohide"

    public init() {}

    public func autohide() -> Bool {
        guard let result = try? Shell.run("/usr/bin/defaults", ["read", domain, key]),
              result.status == 0
        else {
            return false
        }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    public func setAutohide(_ on: Bool) throws {
        let result = try Shell.run("/usr/bin/defaults", [
            "write", domain, key, "-bool", on ? "true" : "false",
        ])
        guard result.status == 0 else {
            throw SwitchDeckError.shell("Could not write \(domain) \(key): \(result.error)")
        }
    }

    public func restartDock() {
        // Exits 1 when the Dock is not running; harmless.
        _ = try? Shell.run("/usr/bin/killall", ["Dock"])
    }
}

public final class DockAutohideSwitch {
    private let preferences: DockPreferences

    public init(preferences: DockPreferences = ShellDockPreferences()) {
        self.preferences = preferences
    }

    public var isOn: Bool { preferences.autohide() }

    public func set(_ on: Bool) throws {
        try preferences.setAutohide(on)
        preferences.restartDock()
    }

    public func toggle() throws {
        try set(!isOn)
    }
}
