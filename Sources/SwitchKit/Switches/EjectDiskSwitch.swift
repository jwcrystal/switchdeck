import AppKit

/// Ejects every removable / ejectable volume, e.g. USB sticks and disk images.
public final class EjectDiskSwitch {
    public init() {}

    public var ejectableVolumes: [URL] {
        let keys: [URLResourceKey] = [
            .volumeIsEjectableKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            if values.volumeIsInternal == true { return false }
            return values.volumeIsEjectable == true || values.volumeIsRemovable == true
        }
    }

    public var subtitle: String? {
        let count = ejectableVolumes.count
        switch count {
        case 0: return t("No disks")
        case 1: return t("1 disk")
        default: return tf("%d disks", count)
        }
    }

    public func ejectAll() throws {
        let volumes = ejectableVolumes
        guard !volumes.isEmpty else {
            throw SwitchDeckError.message(t("There is no ejectable disk right now."))
        }

        var failed: [String] = []
        for url in volumes {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            } catch {
                failed.append("\(url.lastPathComponent) (\(error.localizedDescription))")
            }
        }

        guard failed.isEmpty else {
            throw SwitchDeckError.message(
                tf("Could not eject: %@. A file on the disk may still be open.", failed.joined(separator: ", "))
            )
        }
    }
}
