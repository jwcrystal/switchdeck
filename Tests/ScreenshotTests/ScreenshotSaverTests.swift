import XCTest
@testable import SwitchDeckApp

final class ScreenshotSaverTests: XCTestCase {
    /// A fixed date keeps the formatted name stable.
    private let date = Date(timeIntervalSince1970: 1_760_000_000)

    func testFileNameStartsWithThePrefix() {
        let name = ScreenshotPreferences.fileName(prefix: "SwitchDeck", at: date, format: .png)
        XCTAssertTrue(name.hasPrefix("SwitchDeck Screenshot "))
        XCTAssertTrue(name.hasSuffix(".png"))
    }

    func testEmptyPrefixDropsTheLeadingSpace() {
        XCTAssertTrue(ScreenshotPreferences.fileName(prefix: "", at: date).hasPrefix("Screenshot "))
        XCTAssertTrue(ScreenshotPreferences.fileName(prefix: "   ", at: date).hasPrefix("Screenshot "))
    }

    func testSlashesCannotTurnThePrefixIntoAFolder() {
        let name = ScreenshotPreferences.fileName(prefix: "team/shots", at: date)
        XCTAssertFalse(name.contains("/"))
        XCTAssertTrue(name.hasPrefix("team-shots Screenshot "))
    }

    func testPrefixIsTrimmed() {
        XCTAssertEqual(
            ScreenshotPreferences.sanitizedPrefix("  Work  "),
            "Work"
        )
    }

    /// The name has to follow the format picker, or a JPEG lands as `.png`.
    func testFileNameFollowsTheChosenFormat() {
        XCTAssertTrue(ScreenshotPreferences.fileName(at: date, format: .jpeg).hasSuffix(".jpeg"))
        XCTAssertTrue(ScreenshotPreferences.fileName(at: date, format: .heic).hasSuffix(".heic"))
    }

    /// Each format the picker offers must actually encode, with the right
    /// extension on disk.
    func testWritesEveryFormat() throws {
        let image = NSImage(size: NSSize(width: 24, height: 16))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 16).fill()
        image.unlockFocus()

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("switchdeck-saver-\(UUID().uuidString)")

        for format in ScreenshotPreferences.ImageFormat.allCases {
            let url = try XCTUnwrap(
                ScreenshotSaver.write(
                    image,
                    watermark: nil,
                    folder: folder,
                    format: format,
                    quality: 0.7,
                    date: date
                ),
                "\(format.title) could not be written"
            )
            XCTAssertEqual(url.pathExtension, format.fileExtension)
            XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
        }

        try? FileManager.default.removeItem(at: folder)
    }
}
