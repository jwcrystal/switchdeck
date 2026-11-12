import AppKit
import CoreImage
import SwiftUI

/// A mark drawn on top of a screenshot.
///
/// Points are normalised to the image (0…1, origin top-left) so an annotation
/// survives being displayed at any size and can be rendered at full resolution.
struct Annotation {
    enum Shape {
        case rectangle(from: CGPoint, to: CGPoint)
        case ellipse(from: CGPoint, to: CGPoint)
        case line(from: CGPoint, to: CGPoint)
        case arrow(from: CGPoint, to: CGPoint)
        case pen(points: [CGPoint])
        case highlighter(points: [CGPoint])
        case number(Int, at: CGPoint)
        case mosaic(from: CGPoint, to: CGPoint)
        case blur(from: CGPoint, to: CGPoint)
        case text(String, at: CGPoint)
    }

    var shape: Shape
    var color: Color
    /// Stroke width relative to the image width.
    var lineWidth: CGFloat = 0.004

    static let palette: [Color] = [.red, .yellow, .blue, .white, .black]
}

enum AnnotationRenderer {
    /// Draws the annotations over the capture at full pixel resolution.
    static func render(base: CGImage, annotations: [Annotation]) -> NSImage {
        let width = CGFloat(base.width)
        let height = CGFloat(base.height)
        let output = NSImage(size: NSSize(width: width, height: height))

        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: base, size: NSSize(width: width, height: height))
            .draw(in: NSRect(x: 0, y: 0, width: width, height: height))

        for annotation in annotations {
            draw(annotation, width: width, height: height, base: base)
        }
        output.unlockFocus()

        return output
    }

    private static func draw(_ annotation: Annotation, width: CGFloat, height: CGFloat, base: CGImage?) {
        let color = NSColor(annotation.color)
        color.setStroke()
        color.setFill()

        let lineWidth = max(1, annotation.lineWidth * width)
        let point: (CGPoint) -> NSPoint = { p in
            NSPoint(x: p.x * width, y: height - p.y * height)
        }

        switch annotation.shape {
        case .rectangle(let start, let end):
            let rect = NSRect(x: point(start).x, y: point(end).y,
                              width: point(end).x - point(start).x,
                              height: point(start).y - point(end).y)
            let path = NSBezierPath(rect: rect)
            path.lineWidth = lineWidth
            path.stroke()

        case .ellipse(let start, let end):
            let rect = NSRect(x: point(start).x, y: point(end).y,
                              width: point(end).x - point(start).x,
                              height: point(start).y - point(end).y)
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = lineWidth
            path.stroke()

        case .arrow(let start, let end):
            let a = point(start)
            let b = point(end)
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.move(to: a)
            path.line(to: b)
            path.stroke()

            let angle = atan2(b.y - a.y, b.x - a.x)
            let head = max(lineWidth * 3.2, 10)
            let headPath = NSBezierPath()
            headPath.lineWidth = lineWidth
            headPath.lineCapStyle = .round
            headPath.move(to: b)
            headPath.line(to: NSPoint(x: b.x - head * cos(angle - .pi / 7), y: b.y - head * sin(angle - .pi / 7)))
            headPath.move(to: b)
            headPath.line(to: NSPoint(x: b.x - head * cos(angle + .pi / 7), y: b.y - head * sin(angle + .pi / 7)))
            headPath.stroke()

        case .line(let start, let end):
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.move(to: point(start))
            path.line(to: point(end))
            path.stroke()

        case .highlighter(let points):
            guard let first = points.first else { return }
            color.withAlphaComponent(0.32).setStroke()
            let path = NSBezierPath()
            path.lineWidth = max(6, width * 0.02)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: point(first))
            for p in points.dropFirst() {
                path.line(to: point(p))
            }
            path.stroke()

        case .number(let value, let at):
            let center = point(at)
            let radius = max(11, width * 0.014)
            let circle = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            color.setFill()
            circle.fill()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: radius * 1.15),
                .foregroundColor: NSColor.white,
            ]
            let string = NSAttributedString(string: "\(value)", attributes: attributes)
            let size = string.size()
            string.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))

        case .mosaic(let start, let end):
            let a = point(start)
            let b = point(end)
            let rect = NSRect(
                x: min(a.x, b.x),
                y: min(a.y, b.y),
                width: abs(b.x - a.x),
                height: abs(b.y - a.y)
            )
            guard rect.width > 2, rect.height > 2, let base else { return }

            let cropRect = CGRect(
                x: min(start.x, end.x) * width,
                y: min(start.y, end.y) * height,
                width: abs(end.x - start.x) * width,
                height: abs(end.y - start.y) * height
            )
            guard let crop = base.cropping(to: cropRect) else { return }

            let blocks = max(2, Int(cropRect.width / 14))
            let blocksHigh = max(1, Int(CGFloat(blocks) * cropRect.height / max(1, cropRect.width)))
            let small = NSImage(size: NSSize(width: blocks, height: blocksHigh))
            small.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            NSImage(cgImage: crop, size: NSSize(width: blocks, height: blocksHigh))
                .draw(in: NSRect(x: 0, y: 0, width: blocks, height: blocksHigh))
            small.unlockFocus()

            NSGraphicsContext.current?.imageInterpolation = .none
            small.draw(in: rect)
            NSGraphicsContext.current?.imageInterpolation = .high

        case .blur(let start, let end):
            let a = point(start)
            let b = point(end)
            let rect = NSRect(
                x: min(a.x, b.x),
                y: min(a.y, b.y),
                width: abs(b.x - a.x),
                height: abs(b.y - a.y)
            )
            guard rect.width > 2, rect.height > 2, let base else { return }

            let cropRect = CGRect(
                x: min(start.x, end.x) * width,
                y: min(start.y, end.y) * height,
                width: abs(end.x - start.x) * width,
                height: abs(end.y - start.y) * height
            )
            guard let crop = base.cropping(to: cropRect) else { return }

            let input = CIImage(cgImage: crop)
            let radius = max(6, cropRect.width * 0.012)
            let output = input
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: input.extent)

            guard let blurred = CIContext().createCGImage(output, from: input.extent) else { return }
            NSImage(cgImage: blurred, size: rect.size).draw(in: rect)

        case .pen(let points):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: point(first))
            for p in points.dropFirst() {
                path.line(to: point(p))
            }
            path.stroke()

        case .text(let text, let at):
            let fontSize = max(12, width * 0.022)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: color,
            ]
            let origin = point(at)
            NSAttributedString(string: text, attributes: attributes)
                .draw(at: NSPoint(x: origin.x, y: origin.y - fontSize))
        }
    }
}
