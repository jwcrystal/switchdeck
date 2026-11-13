import SwiftUI

extension ArrowStyle {
    var title: String {
        switch self {
        case .straight: return "Straight arrow"
        case .curved: return "Curved arrow"
        case .elbow: return "Elbow arrow"
        case .sCurve: return "S-curve arrow"
        }
    }
}

/// Actual miniature paths keep the four arrow choices visually distinct.
struct ArrowOptionIcon: Shape {
    let style: ArrowStyle

    func path(in rect: CGRect) -> Path {
        let a = CGPoint(x: rect.minX + 3, y: rect.maxY - 4)
        let b = CGPoint(x: rect.maxX - 3, y: rect.minY + 4)
        let dx = b.x - a.x
        var tangent = a
        var path = Path()
        path.move(to: a)
        switch style {
        case .straight:
            path.addLine(to: b)
        case .curved:
            tangent = CGPoint(x: a.x, y: b.y)
            path.addQuadCurve(to: b, control: tangent)
        case .elbow:
            tangent = CGPoint(x: b.x, y: a.y)
            path.addLine(to: tangent)
            path.addLine(to: b)
        case .sCurve:
            tangent = CGPoint(x: b.x - dx * 0.15, y: a.y + 4)
            path.addCurve(to: b, control1: CGPoint(x: a.x + dx * 0.15, y: b.y - 4), control2: tangent)
        }
        let angle = atan2(b.y - tangent.y, b.x - tangent.x)
        let head: CGFloat = 4
        for side: CGFloat in [-1, 1] {
            path.move(to: b)
            path.addLine(to: CGPoint(x: b.x - head * cos(angle + side * .pi / 6), y: b.y - head * sin(angle + side * .pi / 6)))
        }
        return path
    }
}
