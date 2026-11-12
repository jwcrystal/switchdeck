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

    public func itemCount() -> Int? {
        guard let descriptor = try? Automation.run(#"tell application "Finder" to count items in trash"#) else {
            return nil
        }
        return Int(descriptor.int32Value)
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
            let suffix = failures.count > 3 ? " and \(failures.count - 3) more" : ""
            throw SwitchDeckError.message("Could not delete \(names)\(suffix). Something may still be open.")
        }
    }
}

/// Menu-facing wrapper: "17 items" on the right, one click to empty.
public final class EmptyTrashSwitch {
    private let access: TrashAccess

    public init(access: TrashAccess = FinderTrash()) {
        self.access = access
    }

    public var subtitle: String? {
        guard let count = access.itemCount() else { return "No access" }
        return count == 0 ? "Empty" : "\(count) items"
    }

    public func empty() throws {
        try access.empty()
    }
}
