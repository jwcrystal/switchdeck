import AppKit
import XCTest
@testable import SwitchDeckApp

final class ScreenCaptureCropTests: XCTestCase {
    /// The crop takes the same bottom-left global rect the overlay uses, and
    /// flips it into the image's top-left pixel space.
    func testCropFlipsToImageCoordinates() {
        let screenFrame = CGRect(x: 0, y: 0, width: 100, height: 50)
        guard let image = Self.image(width: 200, height: 100) else {
            return XCTFail("could not build the test image")
        }

        let cropped = ScreenCaptureService.crop(
            image: image,
            to: CGRect(x: 10, y: 10, width: 20, height: 10),
            screenFrame: screenFrame
        )

        XCTAssertEqual(cropped?.width, 40)
        XCTAssertEqual(cropped?.height, 20)
    }

    /// A rect on the second display still lands inside the image.
    func testCropOffsetsByTheScreenOrigin() {
        let screenFrame = CGRect(x: 1440, y: 0, width: 100, height: 50)
        guard let image = Self.image(width: 200, height: 100) else {
            return XCTFail("could not build the test image")
        }

        let cropped = ScreenCaptureService.crop(
            image: image,
            to: CGRect(x: 1450, y: 10, width: 20, height: 10),
            screenFrame: screenFrame
        )

        XCTAssertEqual(cropped?.width, 40)
        XCTAssertEqual(cropped?.height, 20)
    }

    private static func image(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
