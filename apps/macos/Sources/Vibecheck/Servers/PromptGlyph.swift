import SwiftUI

struct PromptShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(0.1, 0.2))
        path.addLine(to: point(0.42, 0.5))
        path.addLine(to: point(0.1, 0.8))
        path.move(to: point(0.52, 0.8))
        path.addLine(to: point(0.92, 0.8))
        return path
    }
}

struct PromptGlyph: View {
    var size: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        PromptShape()
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
