import CoreImage
import CoreText
import XCTest
@testable import SwitchKit

final class TextRecognizerTests: XCTestCase {
    // MARK: - Result

    func testClipboardPrefersCodes() {
        let result = TextRecognizer.Result(lines: ["Scan me"], codes: ["https://example.com"])
        XCTAssertEqual(result.clipboardText, "https://example.com")
        XCTAssertTrue(result.foundCode)
    }

    func testClipboardFallsBackToText() {
        let result = TextRecognizer.Result(lines: ["first", "second"], codes: [])
        XCTAssertEqual(result.clipboardText, "first\nsecond")
        XCTAssertFalse(result.foundCode)
    }

    func testEmptyResultHasNothingToCopy() {
        XCTAssertNil(TextRecognizer.Result(lines: [], codes: []).clipboardText)
        XCTAssertNil(TextRecognizer.Result(lines: ["  "], codes: []).clipboardText)
    }

    func testLanguagesFollowPreferenceOrderAndSupport() {
        XCTAssertEqual(
            TextRecognizer.languages(supported: ["en-US", "zh-Hant", "fr-FR"]),
            ["zh-Hant", "en-US"]
        )
        XCTAssertEqual(TextRecognizer.languages(supported: []), ["en-US"])
        XCTAssertEqual(TextRecognizer.languages(supported: ["fr-FR"]), ["en-US"])
    }

    func testDuplicateCodesAreDropped() {
        XCTAssertEqual(TextRecognizer.unique(["a", "b", "a"]), ["a", "b"])
    }

    // MARK: - Editing helpers

    func testJoinLinesSpacesLatinWords() {
        XCTAssertEqual(TextRecognizer.joinLines("The quick brown\nfox jumps\n\nover"), "The quick brown fox jumps over")
    }

    func testJoinLinesKeepsChineseTight() {
        XCTAssertEqual(TextRecognizer.joinLines("螢幕保持\n開啟，文字\n辨識。"), "螢幕保持開啟，文字辨識。")
    }

    func testJoinLinesMixedScripts() {
        XCTAssertEqual(TextRecognizer.joinLines("使用 Vision\n模型辨識\nKeep Display\nOn"), "使用 Vision模型辨識Keep Display On")
        XCTAssertEqual(TextRecognizer.joinLines("日本語の\nテキスト"), "日本語のテキスト")
        XCTAssertEqual(TextRecognizer.joinLines("한국어\n텍스트"), "한국어텍스트")
    }

    func testJoinLinesTrimsAndHandlesEmpty() {
        XCTAssertEqual(TextRecognizer.joinLines("  one  \n   two "), "one two")
        XCTAssertEqual(TextRecognizer.joinLines(""), "")
        XCTAssertEqual(TextRecognizer.joinLines("single"), "single")
    }

    func testCounts() {
        let counts = TextRecognizer.counts("文字 辨識\n\nab c\n")
        XCTAssertEqual(counts.lines, 2)
        XCTAssertEqual(counts.characters, 7)
        XCTAssertEqual(TextRecognizer.counts("").lines, 0)
    }

    func testOpenableLinkOnlyHTTP() {
        XCTAssertEqual(TextRecognizer.openableLink(in: ["hello", "https://example.com/a"])?.absoluteString, "https://example.com/a")
        XCTAssertNil(TextRecognizer.openableLink(in: ["file:///etc/passwd", "javascript:alert(1)", "ssh://host"]))
        XCTAssertNil(TextRecognizer.openableLink(in: ["https://", "plain text"]))
        XCTAssertEqual(TextRecognizer.openableLink(in: [" http://Example.com "])?.host, "Example.com")
    }

    // MARK: - Vision, on rendered images

    func testReadsEnglishText() throws {
        let image = try XCTUnwrap(Self.render(["SwitchDeck reads text", "Second line 2026"]))
        let result = try TextRecognizer.recognize(image)
        XCTAssertEqual(result.lines.count, 2, "lines: \(result.lines)")
        XCTAssertTrue(result.text.contains("SwitchDeck reads text"), result.text)
        XCTAssertTrue(result.text.contains("2026"), result.text)
        XCTAssertTrue(result.codes.isEmpty)
    }

    func testReadsTraditionalChinese() throws {
        let image = try XCTUnwrap(Self.render(["螢幕保持開啟", "文字辨識"]))
        let result = try TextRecognizer.recognize(image)
        XCTAssertTrue(result.text.contains("螢幕保持開啟"), result.text)
        XCTAssertTrue(result.text.contains("文字辨識"), result.text)
    }

    func testReadsMixedChineseAndEnglish() throws {
        let image = try XCTUnwrap(Self.render(["Keep Display On 螢幕保持開啟", "簡體中文识别测试"]))
        let result = try TextRecognizer.recognize(image)
        XCTAssertTrue(result.text.contains("Keep Display On"), result.text)
        XCTAssertTrue(result.text.contains("螢幕保持開啟"), result.text)
        XCTAssertTrue(result.text.contains("识别测试"), result.text)
    }

    func testReadsQRCode() throws {
        let image = try XCTUnwrap(Self.qrCode("https://github.com/jwcrystal/switchdeck"))
        let result = try TextRecognizer.recognize(image)
        XCTAssertEqual(result.codes, ["https://github.com/jwcrystal/switchdeck"])
        XCTAssertEqual(result.clipboardText, "https://github.com/jwcrystal/switchdeck")
    }

    func testWarmUpLeavesRecognitionWorking() throws {
        TextRecognizer.warmUp()
        let image = try XCTUnwrap(Self.render(["Warm start"]))
        XCTAssertTrue(try TextRecognizer.recognize(image).text.contains("Warm start"))
    }

    func testBlankImageFindsNothing() throws {
        let image = try XCTUnwrap(Self.render([]))
        let result = try TextRecognizer.recognize(image)
        XCTAssertNil(result.clipboardText)
    }

    // MARK: - Fixtures

    /// Black text on white, 2x scale, like a Retina capture.
    private static func render(_ lines: [String]) -> CGImage? {
        let width = 1200, lineHeight = 90
        let height = max(1, lines.count) * lineHeight + 80
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateUIFontForLanguage(.system, 48, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 48, nil)
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: 40, y: height - 40 - (index + 1) * lineHeight + 20)
            CTLineDraw(ctLine, context)
        }
        return context.makeImage()
    }

    private static func qrCode(_ payload: String) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        else { return nil }
        // A white quiet zone around the code, as on a real screen.
        let padded = output.composited(over: CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -60, dy: -60)))
        return CIContext().createCGImage(padded, from: padded.extent)
    }
}
