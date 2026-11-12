import Foundation

/// Toggles Finder's "show all files" flag.
///
/// Finder only re-reads this at launch, so the change is followed by a Finder
/// restart. That closes Finder windows, which is what the original app does too.
public final class ShowHiddenFilesSwitch {
    private let defaults = "/usr/bin/defaults"
    private let killall = "/usr/bin/killall"

    public init() {}

    public func isOn() -> Bool {
        guard let result = try? Shell.run(defaults, ["read", "com.apple.finder", "AppleShowAllFiles"]) else {
            return false
        }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    public func set(_ on: Bool) throws {
        let result = try Shell.run(defaults, [
            "write", "com.apple.finder", "AppleShowAllFiles", "-bool", on ? "true" : "false",
        ])
        guard result.status == 0 else {
            throw SwitchDeckError.shell("Could not write the Finder preference: \(result.error)")
        }
        try restartFinder()
    }

    public func toggle() throws {
        try set(!isOn())
    }

    private func restartFinder() throws {
        let result = try Shell.run(killall, ["Finder"])
        // killall exits 1 when Finder is not running; that is not an error here.
        guard result.status == 0 || result.error.contains("No matching processes") else {
            throw SwitchDeckError.shell("Could not restart Finder: \(result.error)")
        }
    }
}
