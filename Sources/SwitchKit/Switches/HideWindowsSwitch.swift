import AppKit

/// Hides every other regular app — the reversible sibling of Quit All Apps.
///
/// Hidden apps stay running and come back with one click in the Dock, so this is
/// the safe way to clear the screen. SwitchDeck, Finder and background agents are
/// left alone.
public final class HideWindowsSwitch {
    public init() {}

    public var hideTargets: [NSRunningApplication] {
        let ownBundleID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular else { return false }
            guard !app.isTerminated else { return false }
            guard app.bundleIdentifier != ownBundleID else { return false }
            guard app.bundleIdentifier != "com.apple.finder" else { return false }
            return true
        }
    }

    public var subtitle: String? {
        let count = hideTargets.count
        return count == 0 ? "Nothing to hide" : "\(count) apps"
    }

    public func hideAll() throws {
        let targets = hideTargets
        guard !targets.isEmpty else {
            throw SwitchDeckError.message("There is no other app to hide.")
        }

        var failed: [String] = []
        for app in targets where !app.hide() {
            failed.append(app.localizedName ?? app.bundleIdentifier ?? "Unknown")
        }

        guard failed.isEmpty else {
            throw SwitchDeckError.message("Could not hide: \(failed.joined(separator: ", ")).")
        }
    }
}
