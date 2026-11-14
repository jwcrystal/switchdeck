import Foundation

/// A dotted version number, compared component by component.
///
/// A leading `v` is optional, and missing components count as zero, so `0.8`
/// equals `0.8.0` while `0.10.0` is newer than `0.9.1`. Anything that is not a
/// list of integers is unparseable, and the initializer returns nil.
public struct AppVersion: Comparable {
    private let components: [Int]

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        guard !text.isEmpty else { return nil }

        var components: [Int] = []
        for part in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard let value = Int(part) else { return nil }
            components.append(value)
        }
        self.components = components
    }

    private func component(at index: Int) -> Int {
        index < components.count ? components[index] : 0
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        return (0..<count).allSatisfy { lhs.component(at: $0) == rhs.component(at: $0) }
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = lhs.component(at: index)
            let right = rhs.component(at: index)
            if left != right { return left < right }
        }
        return false
    }
}

/// The parts of the latest GitHub release the update alert needs.
public struct ReleaseInfo: Equatable {
    public let version: String
    public let url: URL

    public init(version: String, url: URL) {
        self.version = version
        self.url = url
    }
}

public enum UpdateCheckResult: Equatable {
    case updateAvailable(ReleaseInfo)
    case upToDate
}

/// Compares the running app with the latest GitHub release. Manual only: the
/// caller decides when to run it.
public struct UpdateChecker {
    /// Injected so tests never hit the network.
    public typealias Fetch = (URLRequest) async throws -> (Data, URLResponse)

    private static let latestRelease = URL(
        string: "https://api.github.com/repos/jwcrystal/switchdeck/releases/latest"
    )!

    private struct ReleasePayload: Decodable {
        let tag_name: String
        let html_url: String
    }

    private let currentVersion: String
    private let fetch: Fetch

    public init(
        currentVersion: String,
        fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }
    ) {
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    public func check() async throws -> UpdateCheckResult {
        guard let current = AppVersion(currentVersion) else {
            throw SwitchDeckError.message(t("The current version number could not be read."))
        }

        var request = URLRequest(url: Self.latestRelease)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await fetch(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SwitchDeckError.message(t("The update server returned an error."))
        }

        let payload: ReleasePayload
        do {
            payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        } catch {
            throw SwitchDeckError.message(t("The update server sent an unexpected response."))
        }

        guard let latest = AppVersion(payload.tag_name), let url = URL(string: payload.html_url) else {
            throw SwitchDeckError.message(t("The update server sent a version number that could not be read."))
        }

        if latest > current {
            // Shown next to "You have 0.8.0.", so drop the tag's leading "v".
            let shown = payload.tag_name.trimmingCharacters(in: .whitespacesAndNewlines)
            let version = shown.lowercased().hasPrefix("v") ? String(shown.dropFirst()) : shown
            return .updateAvailable(ReleaseInfo(version: version, url: url))
        }
        return .upToDate
    }
}
