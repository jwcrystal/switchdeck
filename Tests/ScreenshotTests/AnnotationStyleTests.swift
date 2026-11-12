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
}
