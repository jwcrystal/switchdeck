import AppKit

/// Asks every regular app to quit, skipping SwitchDeck and Finder.
///
/// Apps with unsaved work show their own save sheet; there is no forced
/// termination here on purpose.
public final class QuitAllAppsSwitch {
    public init() {}

    public var targetCount: Int {
        quitTargets.count
    }

    public var subtitle: String? {
        let count = targetCount
        switch count {
        case 0: return t("No apps")
        case 1: return t("1 app")
        default: return tf("%d apps", count)
        }
    }

    private var quitTargets: [NSRunningApplication] {
        let ownBundleID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular else { return false }
            guard !app.isTerminated else { return false }
            guard app.bundleIdentifier != ownBundleID else { return false }
            guard app.bundleIdentifier != "com.apple.finder" else { return false }
            return true
        }
    }

    public func quitAll() {
        for app in quitTargets {
            app.terminate()
        }
    }
}
