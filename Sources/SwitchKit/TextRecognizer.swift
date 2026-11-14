import CoreGraphics
import Foundation
import Vision

/// Reads text and QR codes out of an image with the on-device Vision models.
///
/// Nothing leaves the Mac. Recognition always uses the accurate level: the
/// fast level only reads Latin scripts, so it cannot read Chinese at all.
public enum TextRecognizer {
    public struct Result: Equatable {
        /// Recognised lines in reading order.
        public let lines: [String]
        /// Payloads of any QR or other barcodes found.
        public let codes: [String]

        public init(lines: [String], codes: [String]) {
            self.lines = lines
            self.codes = codes
        }

        public var text: String { lines.joined(separator: "\n") }

        /// What to put on the clipboard. A code is what the user framed when
        /// one is present (a QR screenshot has little useful text around it),
        /// so codes win; otherwise the text.
        public var clipboardText: String? {
            if !codes.isEmpty { return codes.joined(separator: "\n") }
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        public var foundCode: Bool { !codes.isEmpty }
    }

    /// Preferred languages; Chinese must come before English or Vision drops
    /// it. Filtered against what the running macOS supports, so an older
    /// release never rejects the request.
    static let preferredLanguages = ["zh-Hant", "zh-Hans", "en-US", "ja-JP", "ko-KR"]

    /// Loads the recognition models with a throwaway request. The first
    /// request in a process pays for loading them (and, the first time after
    /// an OS update, for compiling them, which can take tens of seconds), so
    /// the app calls this at launch and again when a selection starts.
    public static func warmUp() {
        guard let context = CGContext(
            data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        guard let image = context.makeImage() else { return }
        _ = try? VNImageRequestHandler(cgImage: image, options: [:]).perform([makeTextRequest()])
    }

    /// Runs synchronously; call it off the main thread.
    public static func recognize(_ image: CGImage) throws -> Result {
        let textRequest = makeTextRequest()
        let codeRequest = VNDetectBarcodesRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([textRequest, codeRequest])
        } catch {
            throw SwitchDeckError.message(tf("Text recognition failed: %@", error.localizedDescription))
        }

        let lines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let codes = (codeRequest.results ?? []).compactMap(\.payloadStringValue)
        return Result(lines: lines, codes: unique(codes))
    }

    // MARK: - Editing helpers

    /// Joins wrapped lines into one paragraph, the usual fix-up after reading
    /// text that was broken across lines in a page or PDF. No space goes
    /// between CJK characters (or CJK punctuation); a single space goes
    /// between Latin words. Blank lines are dropped.
    public static func joinLines(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var joined = ""
        for line in lines {
            if let last = joined.unicodeScalars.last, let first = line.unicodeScalars.first,
               !isCJK(last), !isCJK(first) {
                joined += " "
            }
            joined += line
        }
        return joined
    }

    /// Lines with text, and characters that are not whitespace.
    public static func counts(_ text: String) -> (lines: Int, characters: Int) {
        let lines = text.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        let characters = text.filter { !$0.isWhitespace }.count
        return (lines, characters)
    }

    /// The first http(s) link among the codes, the only kind worth offering to
    /// open: other schemes could launch arbitrary apps.
    public static func openableLink(in codes: [String]) -> URL? {
        for code in codes {
            guard let url = URL(string: code.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host?.isEmpty == false
            else { continue }
            return url
        }
        return nil
    }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF,   // Hangul Jamo
             0x2E80...0x2FDF,   // CJK radicals, Kangxi
             0x3000...0x303F,   // CJK symbols and punctuation
             0x3040...0x30FF,   // Hiragana, Katakana
             0x3100...0x31FF,   // Bopomofo, Katakana extensions
             0x3400...0x4DBF,   // CJK extension A
             0x4E00...0x9FFF,   // CJK unified ideographs
             0xAC00...0xD7AF,   // Hangul syllables
             0xF900...0xFAFF,   // CJK compatibility ideographs
             0xFE30...0xFE4F,   // CJK compatibility forms
             0xFF00...0xFFEF,   // Fullwidth forms and punctuation
             0x20000...0x2FA1F: // CJK extensions B and later
            return true
        default:
            return false
        }
    }

    // MARK: - Vision

    /// Accurate level, Chinese before English, with language detection.
    /// With Chinese first and no detection, English words get "corrected"
    /// into wrong ones ("reads" -> "reaas"); with English first, Chinese is
    /// dropped. Detection on top of this order reads both.
    static func makeTextRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages(supported: (try? request.supportedRecognitionLanguages()) ?? [])
        request.automaticallyDetectsLanguage = true
        return request
    }

    static func languages(supported: [String]) -> [String] {
        guard !supported.isEmpty else { return ["en-US"] }
        let picked = preferredLanguages.filter(supported.contains)
        return picked.isEmpty ? ["en-US"] : picked
    }

    /// The same QR code can be reported more than once; keep the first.
    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
