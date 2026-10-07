import CompanionCore
import SwiftUI

/// Renders any loader in the library. Each style is a small view in this folder;
/// add a `LoaderStyle` case in CompanionCore and a branch here to extend the library.
///
/// Loaders are clock-driven (`TimelineView`) rather than state-animated so they never
/// get pulled into the panel's expand/collapse spring transactions.
struct LoaderView: View {
    let style: LoaderStyle
    var size: CGFloat = 16
    var color: Color = LoaderPalette.accent

    var body: some View {
        Group {
            switch style {
            case .ring: RingLoader(color: color)
            case .classic: ClassicLoader(color: color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

enum LoaderPalette {
    static let accent = Color(red: 0.32, green: 0.56, blue: 1.0)
}

/// Arc spinning over a faint track (the original "working" indicator).
struct RingLoader: View {
    var color: Color
    var duration: TimeInterval = 1.1

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let line = max(1.5, proxy.size.width / 8)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: line)
                    Circle()
                        .trim(from: 0, to: 0.32)
                        .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: duration) / duration * 360))
                }
                .padding(line / 2)
            }
        }
    }
}

/// Twelve spokes whose opacity fades around the dial (the macOS/iOS activity indicator).
/// Geometry mirrors the CSS reference: spokes are 24% × 8% of the box, rounded, pushed
/// 146% of their length out from the centre, each fading 1 → 0.15 over `duration`
/// with a 1/12 phase offset (so the bright spoke travels clockwise).
struct ClassicLoader: View {
    var color: Color
    var duration: TimeInterval = 1.2

    private static let count = 12

    var body: some View {
        TimelineView(.animation) { context in
            let progress = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration) / duration
            Canvas { ctx, size in
                let side = min(size.width, size.height)
                let length = side * 0.24
                let thickness = side * 0.08
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                // Distance from the box centre to each spoke's centre.
                let offset = length * 1.46

                for index in 0..<Self.count {
                    // CSS delay of (index - 12)/12 ⇒ spoke `index` is that far into its cycle.
                    var phase = progress + Double(Self.count - index) / Double(Self.count)
                    phase -= phase.rounded(.down)
                    let opacity = 1 - 0.85 * phase

                    var spoke = ctx
                    spoke.translateBy(x: center.x, y: center.y)
                    spoke.rotate(by: .degrees(Double(index) * 30))
                    let rect = CGRect(x: offset - length / 2, y: -thickness / 2,
                                      width: length, height: thickness)
                    spoke.fill(Path(roundedRect: rect, cornerRadius: thickness / 2),
                               with: .color(color.opacity(opacity)))
                }
            }
        }
    }
}
