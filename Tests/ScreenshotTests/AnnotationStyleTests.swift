import AppKit
import XCTest
@testable import SwitchDeckApp

final class AnnotationStyleTests: XCTestCase {
    @MainActor
    private func redPixelCount(_ annotation: Annotation) throws -> Int {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
        let base = try XCTUnwrap(context.makeImage())
        let rendered = AnnotationRenderer.render(base: base, annotations: [annotation])
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(rendered.tiffRepresentation)))
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.redComponent > color.greenComponent + 0.2,
                   color.redComponent > color.blueComponent + 0.2 { count += 1 }
            }
        }
        return count
    }

    @MainActor
    func testOutlineHatchAndSolidActuallyRenderDifferently() throws {
        var annotation = Annotation(shape: .rectangle(from: CGPoint(x: 0.15, y: 0.15), to: CGPoint(x: 0.85, y: 0.85)), color: .red, lineWidth: 0.01)
        let outline = try redPixelCount(annotation)
        annotation.fillStyle = .hatched
        let hatched = try redPixelCount(annotation)
        annotation.fillStyle = .solid
        let solid = try redPixelCount(annotation)
        XCTAssertGreaterThan(hatched, outline)
        XCTAssertGreaterThan(solid, hatched)
    }

    @MainActor
    func testSolidDashedAndDottedLinesHaveRealGaps() throws {
        var annotation = Annotation(shape: .line(from: CGPoint(x: 0.1, y: 0.5), to: CGPoint(x: 0.9, y: 0.5)), color: .red, lineWidth: 0.015)
        let solid = try redPixelCount(annotation)
        annotation.linePattern = .dashed
        let dashed = try redPixelCount(annotation)
        annotation.linePattern = .dotted
        let dotted = try redPixelCount(annotation)
        XCTAssertGreaterThan(solid, dashed)
        XCTAssertGreaterThan(dashed, dotted)
        XCTAssertGreaterThan(dotted, 0)
    }

    func testAnnotationStyleRoundTripsThroughComputedStyle() {
        var style = AnnotationStyle()
        style.color = .blue
        style.lineWidth = 0.01
        style.textScale = 0.03
        style.textBubble = true
        style.arrowStyle = .sCurve
        style.fillStyle = .solid
        style.linePattern = .dotted
        style.mosaicBlock = 20
        style.numberStyle = .square
        style.highlighterAlpha = 0.5

        var annotation = Annotation(
            shape: .rectangle(from: CGPoint(x: 0.1, y: 0.1), to: CGPoint(x: 0.9, y: 0.9)),
            style: style
        )

        XCTAssertEqual(annotation.style, style)
        XCTAssertEqual(annotation.color, .blue)
        XCTAssertEqual(annotation.lineWidth, 0.01)
        XCTAssertEqual(annotation.textScale, 0.03)
        XCTAssertTrue(annotation.textBubble)
        XCTAssertEqual(annotation.arrowStyle, .sCurve)
        XCTAssertEqual(annotation.fillStyle, .solid)
        XCTAssertEqual(annotation.linePattern, .dotted)
        XCTAssertEqual(annotation.mosaicBlock, 20)
        XCTAssertEqual(annotation.numberStyle, .square)
        XCTAssertEqual(annotation.highlighterAlpha, 0.5)

        annotation.style.numberStyle = .circle
        annotation.style.lineWidth = 0.006

        XCTAssertEqual(annotation.numberStyle, .circle)
        XCTAssertEqual(annotation.lineWidth, 0.006)
        XCTAssertEqual(annotation.style.fillStyle, .solid, "changing one field keeps the rest")
    }

    @MainActor
    func testChangingStyleChangesRenderedPixels() throws {
        var annotation = Annotation(
            shape: .rectangle(from: CGPoint(x: 0.15, y: 0.15), to: CGPoint(x: 0.85, y: 0.85)),
            style: AnnotationStyle()
        )
        let outline = try redPixelCount(annotation)
        XCTAssertGreaterThan(outline, 0)

        annotation.style.color = .blue
        XCTAssertEqual(try redPixelCount(annotation), 0, "the renderer must follow the edited style")

        annotation.style.color = .red
        annotation.style.fillStyle = .solid
        XCTAssertGreaterThan(try redPixelCount(annotation), outline)
    }
}
