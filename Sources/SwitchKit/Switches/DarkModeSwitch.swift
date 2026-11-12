import Foundation

/// Light / dark appearance.
///
/// Reading goes through `defaults` (no permission needed). Toggling goes through
/// System Events, which is the only way to change appearance for every app at
/// once; that needs Automation permission on first use.
public final class DarkModeSwitch {
    public init() {}

    public var isDark: Bool {
        guard let result = try? Shell.run("/usr/bin/defaults", ["read", "-g", "AppleInterfaceStyle"]) else {
            return false
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "Dark"
    }

    public func toggle() throws {
        try Automation.run("""
        tell application "System Events" to tell appearance preferences to set dark mode to not dark mode
        """)
    }
}
