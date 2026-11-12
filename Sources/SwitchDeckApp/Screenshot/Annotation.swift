import AppKit
import CoreImage
import SwiftUI

enum ArrowStyle: Hashable {
    case straight
    case curved
    case elbow
    case sCurve
}

enum NumberStyle: Hashable {
    case circle
    case square
}

enum ShapeFillStyle: CaseIterable, Hashable {
    case outline, hatched, solid
}

enum LinePattern: CaseIterable, Hashable {
    case solid, dashed, dotted

    func dashLengths(width: CGFloat) -> [CGFloat] {
        switch self {
        case .solid: return []
        case .dashed: return [max(3, width * 3), max(2, width * 2)]
        case .dotted: return [0, max(3, width * 2.5)]
        }
    }
}

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
    /// Font size relative to the image width. Only used by text.
    var textScale: CGFloat = 0.022
    /// Draw text inside a filled bubble instead of directly on the image.
    var textBubble: Bool = false
    /// How `.arrow` is drawn.
    var arrowStyle: ArrowStyle = .straight
    /// Fill rectangles and ellipses instead of only stroking them.
    var fillStyle: ShapeFillStyle = .outline
    var linePattern: LinePattern = .solid
    /// Mosaic block size in pixels.
    var mosaicBlock: CGFloat = 14
    /// Shape of a numbered marker.
    var numberStyle: NumberStyle = .circle
    /// Highlighter opacity (0…1).
    var highlighterAlpha: CGFloat = 0.32

    static let palette: [Color] = [.red, .yellow, .blue, .white, .black]

    /// Normalised bounding box, used for selection and hit testing.
    var bounds: CGRect {
        switch shape {
        case .rectangle(let a, let b),
             .ellipse(let a, let b),
             .line(let a, let b),
             .arrow(let a, let b),
             .mosaic(let a, let b),
             .blur(let a, let b):
            return CGRect(
                x: min(a.x, b.x), y: min(a.y, b.y),
                width: abs(b.x - a.x), height: abs(b.y - a.y)
            )
        case .pen(let points), .highlighter(let points):
            guard let first = points.first else { return .zero }
            var rect = CGRect(origin: first, size: .zero)
            for point in points.dropFirst() {
                rect = rect.union(CGRect(origin: point, size: .zero))
            }
            return rect
        case .number(_, let at), .text(_, let at):
            return CGRect(x: at.x, y: at.y, width: 0.12, height: 0.04)
        }
    }

    func contains(_ point: CGPoint, tolerance: CGFloat = 0.012) -> Bool {
        let box = bounds.insetBy(dx: -tolerance, dy: -tolerance)
        return box.contains(point)
    }

    func moved(by delta: CGPoint) -> Annotation {
        func p(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + delta.x, y: point.y + delta.y)
        }

        var copy = self
        switch shape {
        case .rectangle(let a, let b): copy.shape = .rectangle(from: p(a), to: p(b))
        case .ellipse(let a, let b): copy.shape = .ellipse(from: p(a), to: p(b))
        case .line(let a, let b): copy.shape = .line(from: p(a), to: p(b))
        case .arrow(let a, let b): copy.shape = .arrow(from: p(a), to: p(b))
        case .mosaic(let a, let b): copy.shape = .mosaic(from: p(a), to: p(b))
        case .blur(let a, let b): copy.shape = .blur(from: p(a), to: p(b))
        case .pen(let points): copy.shape = .pen(points: points.map(p))
        case .highlighter(let points): copy.shape = .highlighter(points: points.map(p))
        case .number(let value, let at): copy.shape = .number(value, at: p(at))
        case .text(let text, let at): copy.shape = .text(text, at: p(at))
        }
        return copy
    }

    /// Scales the annotation so its original box fills `target`.
    func scaled(from original: CGRect, to target: CGRect) -> Annotation {
        let scaleX = original.width > 0 ? target.width / original.width : 1
        let scaleY = original.height > 0 ? target.height / original.height : 1

        func p(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: target.minX + (point.x - original.minX) * scaleX,
                y: target.minY + (point.y - original.minY) * scaleY
            )
        }

        var copy = self
        switch shape {
        case .rectangle(let a, let b): copy.shape = .rectangle(from: p(a), to: p(b))
        case .ellipse(let a, let b): copy.shape = .ellipse(from: p(a), to: p(b))
        case .line(let a, let b): copy.shape = .line(from: p(a), to: p(b))
        case .arrow(let a, let b): copy.shape = .arrow(from: p(a), to: p(b))
        case .mosaic(let a, let b): copy.shape = .mosaic(from: p(a), to: p(b))
        case .blur(let a, let b): copy.shape = .blur(from: p(a), to: p(b))
        case .pen(let points): copy.shape = .pen(points: points.map(p))
        case .highlighter(let points): copy.shape = .highlighter(points: points.map(p))
        case .number(let value, let at): copy.shape = .number(value, at: p(at))
        case .text(let text, let at): copy.shape = .text(text, at: p(at))
        }
        return copy
    }
}

enum AnnotationRenderer {
    /// Draws the annotations over the capture at full pixel resolution.
    ///
    /// Rendering into an `NSBitmapImageRep` (one point per pixel) keeps the
    /// output at the capture's pixel size; drawing into an `NSImage(size:)`
    /// would rasterise it again at the screen's backing scale.
    static func render(base: CGImage, annotations: [Annotation], watermark: WatermarkOptions? = nil) -> NSImage {
        let width = base.width
        let height = base.height
        let rect = CGRect(x: 0, y: 0, width: width, height: height)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(cgImage: base, size: NSSize(width: width, height: height))
        }

        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: base, size: rep.size).draw(in: rect)

        for annotation in annotations {
            draw(annotation, in: rect, base: base)
        }
        if let watermark {
            drawWatermark(watermark, in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    /// Draws one annotation into `rect` (bottom-left origin, AppKit space).
    /// `base` is nil for live previews, where mosaic and blur are approximate.
    static func draw(_ annotation: Annotation, in rect: CGRect, base: CGImage?) {
        let color = NSColor(annotation.color)
        color.setStroke()
        color.setFill()

        let lineWidth = max(1, annotation.lineWidth * rect.width)

        func point(_ p: CGPoint) -> NSPoint {
            NSPoint(x: rect.minX + p.x * rect.width, y: rect.maxY - p.y * rect.height)
        }

        switch annotation.shape {
        case .rectangle(let start, let end):
            let a = point(start)
            let b = point(end)
            let path = NSBezierPath(rect: NSRect(
                x: min(a.x, b.x), y: min(a.y, b.y),
                width: abs(b.x - a.x), height: abs(b.y - a.y)
            ))
            path.lineWidth = lineWidth
            drawShape(path, annotation: annotation, lineWidth: lineWidth)

        case .ellipse(let start, let end):
            let a = point(start)
            let b = point(end)
            let path = NSBezierPath(ovalIn: NSRect(
                x: min(a.x, b.x), y: min(a.y, b.y),
                width: abs(b.x - a.x), height: abs(b.y - a.y)
            ))
            path.lineWidth = lineWidth
            drawShape(path, annotation: annotation, lineWidth: lineWidth)

        case .line(let start, let end):
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.move(to: point(start))
            path.line(to: point(end))
            applyPattern(annotation.linePattern, to: path, width: lineWidth)
            path.stroke()

        case .arrow(let start, let end):
            drawArrow(from: point(start), to: point(end), style: annotation.arrowStyle, lineWidth: lineWidth, pattern: annotation.linePattern)

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
            applyPattern(annotation.linePattern, to: path, width: lineWidth)
            path.stroke()

        case .highlighter(let points):
            guard let first = points.first else { return }
            color.withAlphaComponent(annotation.highlighterAlpha).setStroke()
            let path = NSBezierPath()
            path.lineWidth = max(2, rect.width * annotation.lineWidth * 5)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: point(first))
            for p in points.dropFirst() {
                path.line(to: point(p))
            }
            path.stroke()

        case .number(let value, let at):
            let center = point(at)
            let radius = max(11, rect.width * 0.014)
            color.setFill()
            let box = NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            if annotation.numberStyle == .square {
                NSBezierPath(roundedRect: box, xRadius: radius * 0.4, yRadius: radius * 0.4).fill()
            } else {
                NSBezierPath(ovalIn: box).fill()
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: radius * 1.15),
                .foregroundColor: NSColor.white,
            ]
            let string = NSAttributedString(string: "\(value)", attributes: attributes)
            let size = string.size()
            string.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))

        case .mosaic(let start, let end):
            drawPixelEffect(start: start, end: end, rect: rect, base: base, blurred: false, block: annotation.mosaicBlock)

        case .blur(let start, let end):
            drawPixelEffect(start: start, end: end, rect: rect, base: base, blurred: true, block: annotation.mosaicBlock)

        case .text(let text, let at):
            let fontSize = max(12, rect.width * annotation.textScale)
            let origin = point(at)

            if annotation.textBubble {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: NSColor.white,
                ]
                let string = NSAttributedString(string: text, attributes: attributes)
                let textSize = string.size()
                let padding = fontSize * 0.55
                let bubble = NSRect(
                    x: origin.x - padding,
                    y: origin.y - textSize.height - padding * 0.4,
                    width: textSize.width + padding * 2,
                    height: textSize.height + padding * 1.2
                )
                color.setFill()
                NSBezierPath(roundedRect: bubble, xRadius: fontSize * 0.6, yRadius: fontSize * 0.6).fill()
                string.draw(at: NSPoint(x: origin.x, y: origin.y - textSize.height))
            } else {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: color,
                ]
                NSAttributedString(string: text, attributes: attributes)
                    .draw(at: NSPoint(x: origin.x, y: origin.y - fontSize))
            }
        }
    }

    // MARK: - Watermark

    struct WatermarkOptions {
        enum Placement: String, CaseIterable, Identifiable {
            case bottomRight, bottomLeft, topRight, topLeft, center, tiled

            var id: String { rawValue }

            var title: String {
                switch self {
                case .bottomRight: return "Bottom Right"
                case .bottomLeft: return "Bottom Left"
                case .topRight: return "Top Right"
                case .topLeft: return "Top Left"
                case .center: return "Center"
                case .tiled: return "Tiled"
                }
            }

            var symbol: String {
                switch self {
                case .bottomRight: return "arrow.down.right"
                case .bottomLeft: return "arrow.down.left"
                case .topRight: return "arrow.up.right"
                case .topLeft: return "arrow.up.left"
                case .center: return "dot.squareshape"
                case .tiled: return "square.grid.3x3"
                }
            }
        }

        var text: String
        var placement: Placement = .bottomRight
        /// Font size relative to the image width.
        var scale: CGFloat = 0.02
        /// Degrees, counter-clockwise.
        var rotation: CGFloat = 0
        var opacity: CGFloat = 0.6
        var color: NSColor = .white
    }

    static func drawWatermark(_ options: WatermarkOptions, in rect: CGRect) {
        guard !options.text.isEmpty else { return }

        let font = NSFont.systemFont(ofSize: max(10, rect.width * options.scale), weight: .semibold)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = .zero

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: options.color.withAlphaComponent(options.opacity),
            .shadow: shadow,
        ]
        let string = NSAttributedString(string: options.text, attributes: attributes)
        let size = string.size()
        let margin = max(10, rect.width * 0.015)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        // Never let a rotated or tiled watermark spill outside the capture.
        NSGraphicsContext.current?.cgContext.clip(to: rect)

        if options.placement == .tiled {
            let context = NSGraphicsContext.current?.cgContext
            context?.translateBy(x: rect.midX, y: rect.midY)
            context?.rotate(by: (options.rotation - 30) * .pi / 180)

            let stepX = size.width + rect.width * 0.08
            let stepY = size.height * 3.2
            var y = -rect.height
            while y < rect.height {
                var x = -rect.width
                while x < rect.width {
                    string.draw(at: NSPoint(x: x, y: y))
                    x += stepX
                }
                y += stepY
            }
            return
        }

        let origin: NSPoint
        switch options.placement {
        case .bottomRight:
            origin = NSPoint(x: rect.maxX - size.width - margin, y: rect.minY + margin)
        case .bottomLeft:
            origin = NSPoint(x: rect.minX + margin, y: rect.minY + margin)
        case .topRight:
            origin = NSPoint(x: rect.maxX - size.width - margin, y: rect.maxY - size.height - margin)
        case .topLeft:
            origin = NSPoint(x: rect.minX + margin, y: rect.maxY - size.height - margin)
        case .center, .tiled:
            origin = NSPoint(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2
            )
        }

        if options.rotation != 0 {
            let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.rotate(byDegrees: options.rotation)
            transform.translateX(by: -center.x, yBy: -center.y)
            transform.concat()
        }

        string.draw(at: origin)
    }

    // MARK: - Arrows

    private static func applyPattern(_ pattern: LinePattern, to path: NSBezierPath, width: CGFloat) {
        let lengths = pattern.dashLengths(width: width)
        path.lineCapStyle = .round
        lengths.withUnsafeBufferPointer { path.setLineDash($0.baseAddress, count: $0.count, phase: 0) }
    }

    private static func drawShape(_ path: NSBezierPath, annotation: Annotation, lineWidth: CGFloat) {
        if annotation.fillStyle == .solid { path.fill(); return }
        if annotation.fillStyle == .hatched {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let box = path.bounds
            let hatch = NSBezierPath()
            hatch.lineWidth = max(1, lineWidth * 0.5)
            for x in stride(from: box.minX - box.height, through: box.maxX, by: max(6, lineWidth * 3)) {
                hatch.move(to: NSPoint(x: x, y: box.minY))
                hatch.line(to: NSPoint(x: x + box.height, y: box.maxY))
            }
            hatch.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        applyPattern(annotation.linePattern, to: path, width: lineWidth)
        path.stroke()
    }

    private static func drawArrow(from a: NSPoint, to b: NSPoint, style: ArrowStyle, lineWidth: CGFloat, pattern: LinePattern) {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        var tangentEnd: NSPoint = b

        switch style {
        case .straight:
            tangentEnd = a
            path.move(to: a)
            path.line(to: b)

        case .curved:
            let control = controlPoint(from: a, to: b)
            path.move(to: a)
            path.curve(to: b, controlPoint1: control, controlPoint2: control)
            tangentEnd = control

        case .elbow:
            let corner = NSPoint(x: b.x, y: a.y)
            path.move(to: a)
            path.line(to: corner)
            path.line(to: b)
            tangentEnd = corner

        case .sCurve:
            let dx = b.x - a.x
            let dy = b.y - a.y
            let control1 = NSPoint(x: a.x + dx * 0.15, y: a.y + dy * 0.75)
            let control2 = NSPoint(x: a.x + dx * 0.85, y: a.y + dy * 0.25)
            path.move(to: a)
            path.curve(to: b, controlPoint1: control1, controlPoint2: control2)
            tangentEnd = control2
        }

        applyPattern(pattern, to: path, width: lineWidth)
        path.stroke()

        let angle = atan2(b.y - tangentEnd.y, b.x - tangentEnd.x)
        let head = max(lineWidth * 3.4, 10)
        let headPath = NSBezierPath()
        headPath.lineWidth = lineWidth
        headPath.lineCapStyle = .round
        headPath.move(to: b)
        headPath.line(to: NSPoint(x: b.x - head * cos(angle - .pi / 7), y: b.y - head * sin(angle - .pi / 7)))
        headPath.move(to: b)
        headPath.line(to: NSPoint(x: b.x - head * cos(angle + .pi / 7), y: b.y - head * sin(angle + .pi / 7)))
        headPath.stroke()
    }

    private static func controlPoint(from a: NSPoint, to b: NSPoint) -> NSPoint {
        let mid = NSPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(1, hypot(dx, dy))
        let offset = length * 0.22
        return NSPoint(x: mid.x - dy / length * offset, y: mid.y + dx / length * offset)
    }

    // MARK: - Mosaic / blur

    private static func drawPixelEffect(
        start: CGPoint,
        end: CGPoint,
        rect: CGRect,
        base: CGImage?,
        blurred: Bool,
        block: CGFloat
    ) {
        let a = NSPoint(x: rect.minX + start.x * rect.width, y: rect.maxY - start.y * rect.height)
        let b = NSPoint(x: rect.minX + end.x * rect.width, y: rect.maxY - end.y * rect.height)
        let target = NSRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(b.x - a.x), height: abs(b.y - a.y)
        )
        guard target.width > 2, target.height > 2 else { return }

        guard let base else {
            NSColor(calibratedWhite: 0.5, alpha: 0.55).setFill()
            NSBezierPath(rect: target).fill()
            return
        }

        let cropRect = CGRect(
            x: min(start.x, end.x) * CGFloat(base.width),
            y: min(start.y, end.y) * CGFloat(base.height),
            width: abs(end.x - start.x) * CGFloat(base.width),
            height: abs(end.y - start.y) * CGFloat(base.height)
        )
        guard let crop = base.cropping(to: cropRect) else { return }

        if blurred {
            let input = CIImage(cgImage: crop)
            let radius = max(2, block * 0.6)
            let output = input
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: input.extent)
            guard let image = CIContext().createCGImage(output, from: input.extent) else { return }
            NSImage(cgImage: image, size: target.size).draw(in: target)
        } else {
            let blocks = max(2, Int(cropRect.width / max(4, block)))
            let blocksHigh = max(1, Int(CGFloat(blocks) * cropRect.height / max(1, cropRect.width)))
            let small = NSImage(size: NSSize(width: blocks, height: blocksHigh))
            small.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            NSImage(cgImage: crop, size: NSSize(width: blocks, height: blocksHigh))
                .draw(in: NSRect(x: 0, y: 0, width: blocks, height: blocksHigh))
            small.unlockFocus()

            NSGraphicsContext.current?.imageInterpolation = .none
            small.draw(in: target)
            NSGraphicsContext.current?.imageInterpolation = .high
        }
    }
}
