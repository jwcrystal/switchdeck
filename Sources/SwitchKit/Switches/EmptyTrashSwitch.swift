import Foundation

/// Where the Trash lives and how it is emptied.
///
/// Two implementations: Finder (`FinderTrash`, the real thing) and the file
/// system (`FileTrash`, used by tests and as a reference). Reading `~/.Trash`
/// directly needs Full Disk Access, so Finder is the default.
public protocol TrashAccess {
    /// `nil` means "cannot read the Trash" — not "empty".
    func itemCount() -> Int?
    func empty() throws
}

/// Asks Finder, which is the only process that can enumerate every Trash
/// (including the per-volume ones) without Full Disk Access.
public final class FinderTrash: TrashAccess {
    public init() {}

    /// Runs off the main thread (NSAppleScript is main-thread only), so the
    /// count goes through `osascript`.
    public func itemCount() -> Int? {
        guard let result = try? Shell.run(
            "/usr/bin/osascript",
            ["-e", #"tell application "Finder" to count items in trash"#]
        ), result.status == 0 else {
            return nil
        }
        return Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func empty() throws {
        try Automation.run(Self.emptyScript)
    }

    /// Keeps Finder's "warn before emptying" preference as the user left it,
    /// including when emptying fails.
    private static let emptyScript = """
    tell application "Finder"
        set previousWarning to warns before emptying of trash
        try
            set warns before emptying of trash to false
            empty trash
        on error errorMessage number errorNumber
            set warns before emptying of trash to previousWarning
            error errorMessage number errorNumber
        end try
        set warns before emptying of trash to previousWarning
    end tell
    """
}

/// Deletes the contents of a Trash folder directly.
public final class FileTrash: TrashAccess {
    private let url: URL

    public init(url: URL = FileTrash.defaultURL()) {
        self.url = url
    }

    public static func defaultURL() -> URL {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
    }

    public func itemCount() -> Int? {
        // A folder that is not there is an empty Trash. A folder that exists but
        // cannot be listed is a permission problem; that must not look empty.
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isHiddenKey],
            options: []
        ) else {
            return nil
        }
        return contents.filter { item in
            let hidden = (try? item.resourceValues(forKeys: [.isHiddenKey]))?.isHidden ?? false
            return !hidden
        }.count
    }

    public func empty() throws {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []

        var failures: [String] = []
        for item in contents {
            do {
                try FileManager.default.removeItem(at: item)
            } catch {
                failures.append(item.lastPathComponent)
            }
        }

        guard failures.isEmpty else {
            let names = failures.prefix(3).joined(separator: ", ")
            let suffix = failures.count > 3 ? tf(" and %d more", failures.count - 3) : ""
            throw SwitchDeckError.message(
                tf("Could not delete %@%@. Something may still be open.", names, suffix)
            )
        }
    }
}

/// Menu-facing wrapper: "17 items" on the right, one click to empty.
///
/// With `countsInBackground` the subtitle returns the last known count at once
/// and refreshes it on a utility queue, so a slow Finder never stalls the menu.
public final class EmptyTrashSwitch {
    private enum CountState {
        case unknown
        case noAccess
        case items(Int)
    }

    private let access: TrashAccess
    private let countsInBackground: Bool

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "io.github.jwcrystal.switchdeck.trash-count", qos: .utility)
    private var cached = CountState.unknown
    private var refreshInFlight = false
    private var generation = 0

    public init(access: TrashAccess = FinderTrash(), countsInBackground: Bool = false) {
        self.access = access
        self.countsInBackground = countsInBackground
    }

    public var subtitle: String? {
        guard countsInBackground else {
            guard let count = access.itemCount() else { return t("No access") }
            return Self.label(for: count)
        }

        scheduleRefresh()
        lock.lock()
        let state = cached
        lock.unlock()

        switch state {
        case .unknown: return nil
        case .noAccess: return t("No access")
        case .items(let count): return Self.label(for: count)
        }
    }

    public func empty() throws {
        try access.empty()
        guard countsInBackground else { return }
        lock.lock()
        generation += 1
        cached = .items(0)
        lock.unlock()
    }

    /// Blocks until the queued refresh (if any) has finished. For tests.
    func waitForPendingCount() {
        queue.sync {}
    }

    private func scheduleRefresh() {
        lock.lock()
        if refreshInFlight {
            lock.unlock()
            return
        }
        refreshInFlight = true
        let startedAt = generation
        lock.unlock()

        queue.async { [self] in
            let count = access.itemCount()
            lock.lock()
            if generation == startedAt {
                cached = count.map { .items($0) } ?? .noAccess
            }
            refreshInFlight = false
            lock.unlock()
        }
    }

    private static func label(for count: Int) -> String {
        switch count {
        case 0: return t("Empty")
        case 1: return t("1 item")
        default: return tf("%d items", count)
        }
    }
}
