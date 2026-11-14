import AppKit
import Foundation
import UniformTypeIdentifiers

/// Everything Settings › Screenshot changes, in one place.
///
/// Values live in `UserDefaults` so the capture overlay can read them without
/// the settings window being open. Every getter has the same default the
/// settings UI shows, so a fresh install behaves as documented.
enum ScreenshotPreferences {
    // MARK: - Keys

    static let folderKey = "ScreenshotFolder"
    static let prefixKey = "ScreenshotFilenamePrefix"
    static let formatKey = "ScreenshotFormat"
    static let qualityKey = "ScreenshotQuality"
    static let delayKey = "ScreenshotDelay"
    static let colorFormatKey = "ScreenshotColorFormat"
    static let watermarkTextKey = "ScreenshotWatermarkText"
    static let watermarkDefaultKey = "ScreenshotWatermarkDefault"
    static let silentRecognitionKey = "TextRecognitionSilent"
    static let autoCopyRecognitionKey = "TextRecognitionAutoCopy"

    /// The result window also copies the text as it opens, so a quick look
    /// needs no extra click. Off by default; silent recognition always copies.
    static var autoCopyRecognition: Bool {
        get { UserDefaults.standard.bool(forKey: autoCopyRecognitionKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoCopyRecognitionKey) }
    }

    /// Text recognition copies straight to the clipboard and shows a toast
    /// instead of opening the result window. Off by default.
    static var silentRecognition: Bool {
        get { UserDefaults.standard.bool(forKey: silentRecognitionKey) }
        set { UserDefaults.standard.set(newValue, forKey: silentRecognitionKey) }
    }

    // MARK: - Storage

    enum ImageFormat: String, CaseIterable, Identifiable {
        case png, jpeg, heic

        var id: String { rawValue }

        var title: String {
            switch self {
            case .png: return "PNG"
            case .jpeg: return "JPEG"
            case .heic: return "HEIC"
            }
        }

        var utType: UTType {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            case .heic: return .heic
            }
        }

        var fileExtension: String { utType.preferredFilenameExtension ?? "png" }

        /// JPEG and HEIC are the only formats with a quality knob.
        var isLossy: Bool { self != .png }
    }

    enum ColorFormat: Int, CaseIterable, Identifiable {
        case hex, rgb, hsl

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .hex: return "HEX"
            case .rgb: return "RGB"
            case .hsl: return "HSL"
            }
        }

        var next: ColorFormat {
            ColorFormat(rawValue: (rawValue + 1) % ColorFormat.allCases.count) ?? .hex
        }
    }

    // MARK: - Folder and name

    static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    static var folder: URL {
        if let path = UserDefaults.standard.string(forKey: folderKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return downloads
    }

    static var prefix: String {
        sanitizedPrefix(UserDefaults.standard.string(forKey: prefixKey) ?? "SwitchDeck")
    }

    /// A prefix becomes part of a file name, so a slash would quietly turn it
    /// into a folder, and spaces would break the compact `_`-joined scheme.
    static func sanitizedPrefix(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: "-")
    }

    static var imageFormat: ImageFormat {
        ImageFormat(rawValue: UserDefaults.standard.string(forKey: formatKey) ?? "") ?? .png
    }

    /// 0…1, clamped; only meaningful for JPEG and HEIC.
    static var quality: Double {
        guard UserDefaults.standard.object(forKey: qualityKey) != nil else { return 0.9 }
        return min(1, max(0.1, UserDefaults.standard.double(forKey: qualityKey)))
    }

    /// `prefix` defaults to the stored one; the settings pane passes what is
    /// typed so the preview updates before it is saved.
    ///
    /// The name is space-free and sorts chronologically:
    /// `SwitchDeck_Screenshot_2026-11-13_09-07-55.png`.
    static func fileName(
        prefix: String? = nil,
        at date: Date = Date(),
        format: ImageFormat? = nil
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let ext = (format ?? imageFormat).fileExtension
        let stamp = formatter.string(from: date)
        let name = sanitizedPrefix(prefix ?? self.prefix)
        return name.isEmpty
            ? "Screenshot_\(stamp).\(ext)"
            : "\(name)_Screenshot_\(stamp).\(ext)"
    }

    // MARK: - Capture

    /// Seconds the overlay waits. 0 turns the delay off.
    static var delaySeconds: Int {
        let value = UserDefaults.standard.integer(forKey: delayKey)
        return [0, 3, 5, 10].contains(value) ? value : 0
    }

    static var colorFormat: ColorFormat {
        ColorFormat(rawValue: UserDefaults.standard.integer(forKey: colorFormatKey)) ?? .hex
    }

    static func setColorFormat(_ format: ColorFormat) {
        UserDefaults.standard.set(format.rawValue, forKey: colorFormatKey)
    }

    // MARK: - Watermark

    /// Empty means "use the macOS full user name", which is what a new install
    /// gets.
    static var watermarkText: String {
        (UserDefaults.standard.string(forKey: watermarkTextKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var defaultWatermarkText: String {
        let name = NSFullUserName()
        return name.isEmpty ? "SwitchDeck" : name
    }

    static var watermarkOnByDefault: Bool {
        UserDefaults.standard.bool(forKey: watermarkDefaultKey)
    }
}
