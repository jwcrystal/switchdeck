import AppKit
import XCTest
@testable import SwitchDeckApp

final class FixedEdgeCaptureTests: XCTestCase {
    @MainActor
    func testBlankMarginsAndRepeatedRowsDoNotOvercountMovement() throws {
        func frame(offset: Int) throws -> CGImage {
            let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: 0, y: 300)
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            context.setFillColor(NSColor.darkGray.cgColor)
            for index in 0..<12 {
                context.fill(CGRect(x: 20, y: 80 + index * 18 + offset, width: 360, height: 7))
            }
            return try XCTUnwrap(context.makeImage())
        }
        XCTAssertEqual(ScrollingCapture.debugStitch([try frame(offset: 0), try frame(offset: -40)]), 340)
    }

    static func frame(offset: Int) -> CGImage {
        let width = 640, height = 480
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let fixed = y < 60 || y >= 440 || x < 80 || x >= 580
                let row = fixed ? y : y + offset
                let value = UInt8((row * 73 + x * 31 + (row / 9) * (x / 13)) % 223)
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
    func testFixedHeaderFooterAndSidebarsAreNotRepeated() throws {
        let a = Self.frame(offset: 0), b = Self.frame(offset: 40), c = Self.frame(offset: 80)
        let result = try XCTUnwrap(ScrollingCapture.debugCompose([a, b, c]))
        XCTAssertEqual(result.width, 640)
        XCTAssertEqual(result.height, 560)
        let output = NSBitmapImageRep(cgImage: result)
        let first = NSBitmapImageRep(cgImage: a)
        let last = NSBitmapImageRep(cgImage: c)
        for y in [0, 20, 59] {
            XCTAssertEqual(output.colorAt(x: 320, y: y), first.colorAt(x: 320, y: y))
        }
        for y in [520, 539, 559] {
            XCTAssertEqual(output.colorAt(x: 320, y: y), last.colorAt(x: 320, y: y - 80))
        }
        // The moving document, including both seams, must stay continuous.
        for y in [60, 100, 420, 439, 440, 479, 480, 519] {
            let reference = NSBitmapImageRep(cgImage: ScrollingCaptureTests.frame(offset: max(0, y - 400)))
            XCTAssertEqual(output.colorAt(x: 320, y: y), reference.colorAt(x: 320, y: min(y, 400)))
        }
        XCTAssertEqual(output.colorAt(x: 20, y: 100), first.colorAt(x: 20, y: 100))
        XCTAssertEqual(output.colorAt(x: 20, y: 450), output.colorAt(x: 20, y: 500), "Sidebar background extends instead of repeating its controls")
    }
}
