import Foundation

/// Shared access to Finder preferences and the restart they need.
///
/// Finder reads these keys only at launch, so every write is followed by
/// `killall Finder`. That closes Finder windows, which is why the menu labels
/// both switches as doing it.
enum FinderDefaults {
    static func bool(_ key: String) -> Bool? {
        guard let result = try? Shell.run("/usr/bin/defaults", ["read", "com.apple.finder", key]) else {
            return nil
        }
        return parseBool(result.output)
    }

    static func setBool(_ value: Bool, for key: String) throws {
        let result = try Shell.run("/usr/bin/defaults", [
            "write", "com.apple.finder", key, "-bool", value ? "true" : "false",
        ])
        guard result.status == 0 else {
            throw SwitchDeckError.shell("Could not write com.apple.finder \(key): \(result.error)")
        }
        try restart()
    }

    static func restart() throws {
        let result = try Shell.run("/usr/bin/killall", ["Finder"])
        // killall exits 1 when Finder is not running; that is not an error here.
        guard result.status == 0 || result.error.contains("No matching processes") else {
            throw SwitchDeckError.shell("Could not restart Finder: \(result.error)")
        }
    }

    static func parseBool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }
}
