import AppKit
import XCTest
@testable import SwitchDeckApp

final class ScrollingCaptureTests: XCTestCase {
    /// Real top-left image buffers, not CGContext drawings whose flipped
    /// coordinate system could accidentally reverse the scrolling fixture.
    static func frame(offset: Int, blankBand: Bool = false) -> CGImage {
        let width = 640, height = 480
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let row = y + offset
            for x in 0..<width {
                let blank = blankBand && (260..<440).contains(row)
                let value = blank ? UInt8(255) : UInt8((row * 73 + x * 31 + (row / 9) * (x / 13)) % 223)
                let i = (y * width + x) * 4
                bytes[i] = value
                bytes[i + 1] = value
                bytes[i + 2] = value
            }
        }
        let data = Data(bytes) as CFData
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: data)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    @MainActor
    func testTopLeftFramesMovingUpGrowTheScreenshot() {
        let a = Self.frame(offset: 0), b = Self.frame(offset: 40)
        XCTAssertEqual(ScrollingCapture.detectShift(from: a, to: b), 40)
        XCTAssertEqual(ScrollingCapture.debugStitch([a, b]), 520)
    }

    @MainActor
    func testLargerScrollStillGrowsTheScreenshot() {
        let a = Self.frame(offset: 0), b = Self.frame(offset: 160)
        XCTAssertEqual(ScrollingCapture.detectShift(from: a, to: b), 160)
        XCTAssertEqual(ScrollingCapture.debugStitch([a, b]), 640)
    }

    @MainActor
    func testNonRoundOffsetsAreRefinedToNativePixels() {
        let a = Self.frame(offset: 0)
        for offset in [1, 3, 17, 41, 159, 241, 319] {
            XCTAssertEqual(ScrollingCapture.detectShift(from: a, to: Self.frame(offset: offset)), offset)
        }
    }

    @MainActor
    func testUnmatchedFrameDoesNotReplaceTheLastGoodAnchor() {
        let a = Self.frame(offset: 0), b = Self.frame(offset: 41)
        let unrelated = Self.frame(offset: 1200)
        XCTAssertEqual(ScrollingCapture.debugStitch([a, unrelated, b]), 521)
    }

    @MainActor
    func testUpwardThenDownwardScrollDoesNotDuplicateContent() {
        let a = Self.frame(offset: 0), b = Self.frame(offset: 41)
        let c = Self.frame(offset: 82)
        XCTAssertEqual(ScrollingCapture.debugStitch([a, b, a, b, c]), 562)
    }

    @MainActor
    func testStitchedPixelsMatchTheContinuousDocument() throws {
        let offsets = [0, 41, 82, 241, 319]
        let result = try XCTUnwrap(ScrollingCapture.debugCompose(offsets.map { Self.frame(offset: $0) }))
        XCTAssertEqual(result.height, 799)
        let rep = NSBitmapImageRep(cgImage: result)
        // Compare both sides of every seam, not only the final image height.
        for y in [0, 1, 479, 480, 519, 520, 521, 560, 561, 562, 720, 721, 798] {
            let expectedFrame = NSBitmapImageRep(cgImage: Self.frame(offset: y))
            for x in [0, 73, 319, 639] {
                let actual = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let expected = try XCTUnwrap(expectedFrame.colorAt(x: x, y: 0)?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 1.0 / 255, "x=\(x), y=\(y)")
            }
        }
    }

    @MainActor
    func testDoneWaitsForTheInFlightFrame() async {
        let began = expectation(description: "Frame capture is in flight")
        let finished = expectation(description: "Done returns the captured image")
        var continuation: CheckedContinuation<CGImage?, Never>?
        var finishCount = 0
        let capture = ScrollingCapture(region: .zero) {
            await withCheckedContinuation {
                continuation = $0
                began.fulfill()
            }
        }
        capture.onFinish = { image in
            finishCount += 1
            XCTAssertEqual(image?.height, 480)
            finished.fulfill()
        }
        capture.start()
        await fulfillment(of: [began], timeout: 1)
        capture.stop()
        XCTAssertEqual(finishCount, 0)
        continuation?.resume(returning: Self.frame(offset: 0))
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(finishCount, 1)
    }

    @MainActor
    func testIdenticalFramesDoNotGrowEvenWithBlankArea() {
        let a = Self.frame(offset: 0, blankBand: true)
        XCTAssertEqual(ScrollingCapture.detectShift(from: a, to: a), 0)
        XCTAssertEqual(ScrollingCapture.debugStitch([a, a, a]), 480)
    }

    @MainActor
    func testBlankAreaAtTheMatchingBandDoesNotHideScrolling() {
        let a = Self.frame(offset: 0, blankBand: true)
        let b = Self.frame(offset: 40, blankBand: true)
        XCTAssertEqual(ScrollingCapture.detectShift(from: a, to: b), 40)
        XCTAssertEqual(ScrollingCapture.debugStitch([a, b]), 520)
    }

    @MainActor
    func testPauseDoesNotFinishWithoutDone() async {
        let a = Self.frame(offset: 0), b = Self.frame(offset: 40)
        var count = 0
        let capture = ScrollingCapture(region: .zero) {
            count += 1
            return count == 1 ? a : b
        }
        capture.start()
        let pause = expectation(description: "Pause for more than the former idle timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { pause.fulfill() }
        await fulfillment(of: [pause], timeout: 7)
        XCTAssertGreaterThan(count, 37, "The real capture timer must run")
        XCTAssertTrue(capture.isRunning, "Only Done or Cancel should end a capture")
        capture.stop()
    }
}
