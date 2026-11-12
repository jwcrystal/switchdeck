import AppKit
import XCTest
@testable import SwitchDeckApp

final class HorizontalCaptureTests: XCTestCase {
    static func frame(offset: Int, fixedEdges: Bool = false) -> CGImage {
        let width = 480, height = 640
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let fixed = fixedEdges && (x < 60 || x >= 440 || y < 80 || y >= 580)
                let column = fixed ? x : x + offset
                let value = UInt8((column * 73 + y * 31 + (column / 9) * (y / 13)) % 223)
                let i = (y * width + x) * 4
                data[i] = value; data[i + 1] = value; data[i + 2] = value
            }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(data) as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
    }

    @MainActor
    func testHorizontalOutputKeepsOrientationAndPixelAccurateSeams() throws {
        let result = try XCTUnwrap(ScrollingCapture.debugCompose([0, 41, 82].map { Self.frame(offset: $0) }, direction: .horizontal))
        XCTAssertEqual(result.width, 562)
        XCTAssertEqual(result.height, 640)
        let output = NSBitmapImageRep(cgImage: result)
        for x in [0, 1, 479, 480, 520, 521, 561] {
            let reference = NSBitmapImageRep(cgImage: Self.frame(offset: max(0, x - 400)))
            for y in [0, 73, 320, 639] {
                XCTAssertEqual(output.colorAt(x: x, y: y), reference.colorAt(x: min(x, 400), y: y), "x=\(x), y=\(y)")
            }
        }
    }

    @MainActor
    func testHorizontalFixedEdgesArePreservedOnce() throws {
        let a = Self.frame(offset: 0, fixedEdges: true)
        let b = Self.frame(offset: 80, fixedEdges: true)
        let result = try XCTUnwrap(ScrollingCapture.debugCompose([a, b], direction: .horizontal))
        XCTAssertEqual(result.width, 560)
        XCTAssertEqual(result.height, 640)
        let output = NSBitmapImageRep(cgImage: result)
        let first = NSBitmapImageRep(cgImage: a), last = NSBitmapImageRep(cgImage: b)
        for x in [0, 20, 59] { XCTAssertEqual(output.colorAt(x: x, y: 320), first.colorAt(x: x, y: 320)) }
        for x in [520, 539, 559] { XCTAssertEqual(output.colorAt(x: x, y: 320), last.colorAt(x: x - 80, y: 320)) }
        for x in [60, 100, 439, 440, 479, 480, 519] {
            let reference = NSBitmapImageRep(cgImage: Self.frame(offset: max(0, x - 400)))
            XCTAssertEqual(output.colorAt(x: x, y: 320), reference.colorAt(x: min(x, 400), y: 320))
        }
        XCTAssertEqual(output.colorAt(x: 100, y: 20), first.colorAt(x: 100, y: 20))
        XCTAssertEqual(output.colorAt(x: 450, y: 20), output.colorAt(x: 500, y: 20))
    }

    @MainActor
    func testHorizontalPauseAndBacktrackingDoNotDuplicateColumns() throws {
        let a = Self.frame(offset: 0), b = Self.frame(offset: 41), c = Self.frame(offset: 82)
        let result = try XCTUnwrap(ScrollingCapture.debugCompose([a, b, b, a, b, c], direction: .horizontal))
        XCTAssertEqual(result.width, 562)
        XCTAssertEqual(result.height, 640)
    }
}
