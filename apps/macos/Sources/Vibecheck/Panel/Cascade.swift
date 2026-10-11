import SwiftUI

/// Which page the expanded panel shows.
enum PanelPage: Equatable {
    case sessions
    case settings
}

/// One item in a staggered page change. Items of the leaving page slide out toward
/// `side` one after another; items of the arriving page follow once the old ones
/// have mostly cleared. Same language as the row stagger on expand.
struct CascadeItem: ViewModifier {
    let shown: Bool
    let index: Int
    /// Where the item rests while hidden. Sessions sit "back" (leading) behind
    /// Settings, and off toward the screen edge (trailing) while collapsed.
    let side: HorizontalEdge
    /// `true` for a page change (leave first, then arrive); `false` for the quicker
    /// expand/collapse timing the rows have always used.
    let paced: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let distance: CGFloat = reduceMotion ? 0 : (paced ? 28 : 24)
        let step = Double(min(index, 6))
        content
            .offset(x: shown ? 0 : (side == .leading ? -distance : distance))
            .opacity(shown ? 1 : 0)
            .animation(animation(step: step), value: shown)
    }

    private func animation(step: Double) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.18) }
        switch (shown, paced) {
        case (true, true): return .spring(response: 0.42, dampingFraction: 0.86).delay(0.14 + step * 0.045)
        case (true, false): return .spring(response: 0.5, dampingFraction: 0.7).delay(0.04 + step * 0.04)
        case (false, true): return .easeOut(duration: 0.2).delay(step * 0.03)
        case (false, false): return .easeOut(duration: 0.12)
        }
    }
}

extension View {
    func cascade(shown: Bool, index: Int, side: HorizontalEdge, paced: Bool = true) -> some View {
        modifier(CascadeItem(shown: shown, index: index, side: side, paced: paced))
    }
}
