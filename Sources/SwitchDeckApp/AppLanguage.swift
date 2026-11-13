import AppKit
import Foundation
import SwitchKit

/// The interface language, stored as the app's own `AppleLanguages` default.
///
/// macOS resolves a bundle's localisations once, when it launches, so nothing
/// here can change the language of the running process. Picking a language
/// writes the preference and offers a relaunch; "system" removes the key and
/// lets the usual macOS preference decide again.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case traditionalChinese

    var id: String { rawValue }

    static let defaultsKey = "AppleLanguages"

    static var current: AppLanguage {
        // Read the app's own stored value, not the effective one: without a
        // stored key the app is following the system, even though
        // `UserDefaults.standard` would report the inherited language.
        let stored = UserDefaults.standard
            .persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            .flatMap { $0["AppleLanguages"] as? [String] }
        guard let first = stored?.first else { return .system }
        return first.hasPrefix("zh") ? .traditionalChinese : .english
    }

    var title: String {
        switch self {
        case .system: return t("System")
        case .english: return "English"
        case .traditionalChinese: return "繁體中文"
        }
    }

    /// `nil` means "let the system decide", which is the absence of the key.
    var appleLanguages: [String]? {
        switch self {
        case .system: return nil
        case .english: return ["en"]
        case .traditionalChinese: return ["zh-Hant"]
        }
    }

    func apply() {
        if let languages = appleLanguages {
            UserDefaults.standard.set(languages, forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
    }

    /// Starts a fresh instance and quits this one. The delay lets the single
    /// instance lock clear before the new process asks for it.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.6; /usr/bin/open -n \"\(path)\""]
        try? process.run()
        NSApp.terminate(nil)
    }
}
