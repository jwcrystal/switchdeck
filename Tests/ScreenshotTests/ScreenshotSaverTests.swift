import XCTest
@testable import SwitchDeckApp

final class ScreenshotSaverTests: XCTestCase {
    /// A fixed date keeps the formatted name stable.
    private let date = Date(timeIntervalSince1970: 1_760_000_000)

    func testFileNameStartsWithThePrefix() {
        let name = ScreenshotPreferences.fileName(prefix: "SwitchDeck", at: date, format: .png)
        XCTAssertTrue(name.hasPrefix("SwitchDeck_Screenshot_"))
        XCTAssertTrue(name.hasSuffix(".png"))
        XCTAssertFalse(name.contains(" "))
    }

    func testEmptyPrefixDropsTheLeadingSeparator() {
        XCTAssertTrue(ScreenshotPreferences.fileName(prefix: "", at: date).hasPrefix("Screenshot_"))
        XCTAssertTrue(ScreenshotPreferences.fileName(prefix: "   ", at: date).hasPrefix("Screenshot_"))
    }

    func testSlashesCannotTurnThePrefixIntoAFolder() {
        let name = ScreenshotPreferences.fileName(prefix: "team/shots", at: date)
        XCTAssertFalse(name.contains("/"))
        XCTAssertTrue(name.hasPrefix("team-shots_Screenshot_"))
    }

    /// Spaces would break the space-free scheme, so they become dashes.
    func testWhitespaceBecomesDashes() {
        XCTAssertEqual(ScreenshotPreferences.sanitizedPrefix("  My  Shots  "), "My-Shots")
        XCTAssertEqual(ScreenshotPreferences.sanitizedPrefix("Work"), "Work")
    }

    /// The name has to follow the format picker, or a JPEG lands as `.png`.
    func testFileNameFollowsTheChosenFormat() {
        XCTAssertTrue(ScreenshotPreferences.fileName(at: date, format: .jpeg).hasSuffix(".jpeg"))
        XCTAssertTrue(ScreenshotPreferences.fileName(at: date, format: .heic).hasSuffix(".heic"))
    }

    /// Each format the picker offers must actually encode, with the right
    /// extension on disk.
    func testWritesEveryFormat() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("switchdeck-saver-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        for format in ScreenshotPreferences.ImageFormat.allCases {
            let url = try XCTUnwrap(
                ScreenshotSaver.write(
                    Self.image(),
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
    }

    /// Two captures in the same second keep both files.
    func testSameSecondDoesNotOverwrite() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("switchdeck-saver-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = try XCTUnwrap(ScreenshotSaver.write(
            Self.image(), watermark: nil, folder: folder, format: .png, quality: 0.9, date: date
        ))
        let second = try XCTUnwrap(ScreenshotSaver.write(
            Self.image(), watermark: nil, folder: folder, format: .png, quality: 0.9, date: date
        ))

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.lastPathComponent.hasSuffix("_2.png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }

    private static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 16))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 16).fill()
        image.unlockFocus()
        return image
    }
}
