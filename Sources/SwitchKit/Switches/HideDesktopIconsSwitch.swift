import Foundation

/// Hides the icons Finder draws on the desktop, leaving the wallpaper alone.
///
/// Stored in `com.apple.finder CreateDesktop`; Finder only reads it at launch,
/// so the change is followed by a Finder restart.
public final class HideDesktopIconsSwitch {
    public init() {}

    /// A missing key means Finder's default: icons are shown.
    public var areIconsHidden: Bool {
        !(FinderDefaults.bool("CreateDesktop") ?? true)
    }

    public func set(hidden: Bool) throws {
        try FinderDefaults.setBool(!hidden, for: "CreateDesktop")
    }

    public func toggle() throws {
        try set(hidden: !areIconsHidden)
    }
}
