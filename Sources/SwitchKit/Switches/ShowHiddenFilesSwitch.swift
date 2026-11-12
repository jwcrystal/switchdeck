import Foundation

/// Toggles Finder's "show all files" flag.
///
/// Finder only re-reads this at launch, so the change is followed by a Finder
/// restart. That closes Finder windows, which is what the original app does too.
public final class ShowHiddenFilesSwitch {
    public init() {}

    public func isOn() -> Bool {
        FinderDefaults.bool("AppleShowAllFiles") ?? false
    }

    public func set(_ on: Bool) throws {
        try FinderDefaults.setBool(on, for: "AppleShowAllFiles")
    }

    public func toggle() throws {
        try set(!isOn())
    }
}
