import AppKit
import XCTest
@testable import SwitchDeckApp

final class RecognitionLayoutTests: XCTestCase {
    private let screen = CGSize(width: 1440, height: 900)

    func testWideSingleLineGetsASmallStackedWindow() {
        // The 1400 x 120 px demo: one line of terminal text on a Retina screen.
        let layout = RecognitionLayout(imagePixels: CGSize(width: 1400, height: 120), scale: 2, visible: screen, lineCount: 1)
        XCTAssertTrue(layout.stacked)
        XCTAssertEqual(layout.imageSize, CGSize(width: 700, height: 60))
        XCTAssertEqual(layout.textHeight, RecognitionLayout.minTextHeight)
        XCTAssertEqual(layout.windowSize, NSSize(width: 732, height: 60 + 32 + 84 + 48))
    }

    func testTallImageSitsBesideTheText() {
        let layout = RecognitionLayout(imagePixels: CGSize(width: 1000, height: 1100), scale: 2, visible: screen, lineCount: 8)
        XCTAssertFalse(layout.stacked)
        XCTAssertEqual(layout.imageSize.width, 420, accuracy: 0.01)
        XCTAssertEqual(layout.windowSize.width, 420 + 32 + RecognitionLayout.sideTextWidth, accuracy: 0.01)
        // The image is taller than eight lines of text, so it sets the height.
        XCTAssertEqual(layout.windowSize.height, layout.imageSize.height + 32 + 48, accuracy: 0.01)
    }

    func testTextHeightGrowsWithLinesUpToTheCap() {
        let size = CGSize(width: 1400, height: 120)
        let three = RecognitionLayout(imagePixels: size, scale: 2, visible: screen, lineCount: 3)
        let ten = RecognitionLayout(imagePixels: size, scale: 2, visible: screen, lineCount: 10)
        let hundred = RecognitionLayout(imagePixels: size, scale: 2, visible: screen, lineCount: 100)
        XCTAssertLessThan(three.textHeight, ten.textHeight)
        XCTAssertEqual(hundred.textHeight, RecognitionLayout.maxTextHeight)
    }

    func testTinyCaptureKeepsTheMinimumWidth() {
        let layout = RecognitionLayout(imagePixels: CGSize(width: 120, height: 40), scale: 2, visible: screen, lineCount: 1)
        XCTAssertEqual(layout.windowSize.width, RecognitionLayout.minWidth)
    }

    func testWindowNeverExceedsTheScreen() {
        let small = CGSize(width: 800, height: 500)
        let layout = RecognitionLayout(imagePixels: CGSize(width: 5000, height: 3000), scale: 1, visible: small, lineCount: 100)
        XCTAssertLessThanOrEqual(layout.windowSize.width, small.width * 0.8)
        XCTAssertLessThanOrEqual(layout.windowSize.height, small.height * 0.8)
    }
}
