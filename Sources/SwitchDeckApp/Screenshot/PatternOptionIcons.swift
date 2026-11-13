import SwiftUI

struct FillOptionIcon: View {
    let style: ShapeFillStyle
    let ellipse: Bool

    var body: some View {
        Canvas { context, size in
            let box = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let path = ellipse ? Path(ellipseIn: box) : Path(box)
            if style == .solid {
                context.fill(path, with: .foreground)
            } else {
                if style == .hatched {
                    var clipped = context
                    clipped.clip(to: path)
                    var stripes = Path()
                    for x in stride(from: -size.height, through: size.width, by: 5) {
                        stripes.move(to: CGPoint(x: x, y: 0))
                        stripes.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    }
                    clipped.stroke(stripes, with: .foreground, lineWidth: 1)
                }
                context.stroke(path, with: .foreground, lineWidth: 1.4)
            }
        }
    }
}

struct LinePatternIcon: View {
    let pattern: LinePattern

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 2, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: pattern.dashLengths(width: 1.5)))
        }
    }
}
