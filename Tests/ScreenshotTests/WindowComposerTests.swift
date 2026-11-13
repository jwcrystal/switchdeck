import AppKit
import XCTest
@testable import SwitchDeckApp

final class WindowComposerTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)

    func testCanvasFitsTheSelectedWindowExactly() {
        let target = CaptureWindowTarget(
            id: 1,
            rect: CGRect(x: 100, y: 100, width: 200, height: 120)
        )
        let canvas = WindowComposer.canvas(for: [target], screenBounds: screen)
        XCTAssertEqual(canvas, target.rect, "Window capture must not add padding outside the selection")
    }

    func testCanvasFitsTheUnionOfSelectedWindows() {
        let first = CaptureWindowTarget(id: 1, rect: CGRect(x: 10, y: 10, width: 100, height: 100))
        let second = CaptureWindowTarget(id: 2, rect: CGRect(x: 300, y: 60, width: 80, height: 60))
        let canvas = WindowComposer.canvas(for: [first, second], screenBounds: screen)
        XCTAssertEqual(canvas, first.rect.union(second.rect))
    }

    func testCanvasClipsOnlyThePortionOutsideTheScreen() {
        let target = CaptureWindowTarget(id: 1, rect: CGRect(x: -20, y: 650, width: 100, height: 100))
        XCTAssertEqual(WindowComposer.canvas(for: [target], screenBounds: screen),
                       CGRect(x: 0, y: 650, width: 80, height: 50))
    }

    func testComposePreservesAsymmetricVerticalPositions() throws {
        let canvas = CGRect(x: 10, y: 30, width: 200, height: 240)
        let red = Self.image(.red, width: 60, height: 40)
        let blue = Self.image(.blue, width: 60, height: 40)
        let image = try XCTUnwrap(WindowComposer.compose(shots: [
            (red, CGRect(x: 30, y: 50, width: 60, height: 40)),
            (blue, CGRect(x: 130, y: 190, width: 60, height: 40)),
        ], canvas: canvas, scale: 1))
        let bitmap = NSBitmapImageRep(cgImage: image)
        // Bottom-left screen coordinates become top-left image row indices.
        XCTAssertEqual(bitmap.colorAt(x: 50, y: 200)?.redComponent ?? 0, 1, accuracy: 0.05)
        XCTAssertEqual(bitmap.colorAt(x: 150, y: 60)?.blueComponent ?? 0, 1, accuracy: 0.05)
        XCTAssertLessThan(bitmap.colorAt(x: 50, y: 40)?.alphaComponent ?? 1, 0.01,
                          "The lower window must not be mirrored into the upper half")
    }

    func testScreenEdgeClippingCropsInsteadOfMovingOrShrinkingTheWindow() throws {
        let target = CaptureWindowTarget(id: 1, rect: CGRect(x: -20, y: 650, width: 100, height: 100))
        let canvas = try XCTUnwrap(WindowComposer.canvas(for: [target], screenBounds: screen))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // The blue upper half is off-screen; the visible lower half has red
        // and green columns, with 20 points of red clipped at the left edge.
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        context.setFillColor(NSColor.green.cgColor)
        context.fill(CGRect(x: 50, y: 0, width: 50, height: 50))
        let source = try XCTUnwrap(context.makeImage())
        let image = try XCTUnwrap(WindowComposer.compose(shots: [(source, target.rect)], canvas: canvas, scale: 2))
        XCTAssertEqual(image.width, 160)
        XCTAssertEqual(image.height, 100)
        let bitmap = NSBitmapImageRep(cgImage: image)
        XCTAssertGreaterThan(bitmap.colorAt(x: 10, y: 20)?.redComponent ?? 0, 0.85)
        XCTAssertGreaterThan(bitmap.colorAt(x: 120, y: 20)?.greenComponent ?? 0, 0.85)
        XCTAssertLessThan(bitmap.colorAt(x: 10, y: 20)?.blueComponent ?? 1, 0.1)
        XCTAssertEqual(bitmap.colorAt(x: 10, y: 20)?.alphaComponent, 1)
    }

    func testCanvasOfNothingIsNil() {
        XCTAssertNil(WindowComposer.canvas(for: [], screenBounds: screen))
    }

    func testComposeKeepsWindowsAtTheirRelativePositions() {
        let red = Self.image(.red, width: 100, height: 80)
        let blue = Self.image(.blue, width: 100, height: 80)
        let canvas = CGRect(x: 0, y: 0, width: 260, height: 140)
        let shots: [(image: CGImage, rect: CGRect)] = [
            (red, CGRect(x: 20, y: 30, width: 100, height: 80)),
            (blue, CGRect(x: 140, y: 30, width: 100, height: 80)),
        ]

        guard let image = WindowComposer.compose(shots: shots, canvas: canvas, scale: 1) else {
            return XCTFail("the composer returned no image")
        }

        XCTAssertEqual(image.width, 260)
        XCTAssertEqual(image.height, 140)

        let bitmap = NSBitmapImageRep(cgImage: image)
        // NSBitmapImageRep counts rows from the top; the window's bottom-left
        // rect is 30…110, so its middle row is 70 either way.
        XCTAssertEqual(bitmap.colorAt(x: 70, y: 70)?.redComponent ?? 0, 1, accuracy: 0.05)
        XCTAssertEqual(bitmap.colorAt(x: 190, y: 70)?.blueComponent ?? 0, 1, accuracy: 0.05)
    }

    func testComposeLeavesTheMarginTransparentAndPaintsAShadow() {
        // A caller-supplied canvas may contain gaps between selected windows;
        // the composer can draw shadows there without expanding the canvas.
        let margin: CGFloat = 28
        let shot = Self.image(.red, width: 100, height: 80)
        let canvas = CGRect(
            x: 0,
            y: 0,
            width: 100 + margin * 2,
            height: 80 + margin * 2
        )
        let rect = CGRect(x: margin, y: margin, width: 100, height: 80)

        guard let image = WindowComposer.compose(shots: [(shot, rect)], canvas: canvas, scale: 1)
        else { return XCTFail("the composer returned no image") }
        let bitmap = NSBitmapImageRep(cgImage: image)

        // Far corner: outside both the window and the shadow.
        XCTAssertEqual(bitmap.colorAt(x: 1, y: 1)?.alphaComponent ?? 1, 0, accuracy: 0.01)

        // Just below the window: the window ends at top-left row 108, and the
        // shadow falls below that in screen space.
        let shadowAlpha = bitmap.colorAt(x: Int(canvas.width / 2), y: 114)?.alphaComponent ?? 0
        XCTAssertGreaterThan(shadowAlpha, 0.01)
        XCTAssertLessThan(shadowAlpha, 1)
    }

    func testComposeRendersAtTheRequestedScale() {
        let shot = Self.image(.green, width: 100, height: 80)
        let canvas = CGRect(x: 0, y: 0, width: 160, height: 140)

        guard let image = WindowComposer.compose(
            shots: [(shot, CGRect(x: 30, y: 30, width: 100, height: 80))],
            canvas: canvas,
            scale: 2
        ) else { return XCTFail("the composer returned no image") }

        XCTAssertEqual(image.width, 320)
        XCTAssertEqual(image.height, 280)
    }

    private static func image(_ color: NSColor, width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(color.usingColorSpace(.deviceRGB)!.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
