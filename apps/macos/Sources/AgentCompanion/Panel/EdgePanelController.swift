import AppKit
import CompanionCore
import SwiftUI

/// Shared geometry so the AppKit hit-testing and the SwiftUI layout agree exactly.
enum PanelMetrics {
    /// Radius of the concave "flare" where the tab meets the screen edge.
    static let flare: CGFloat = 14
    /// Radius of the convex corners on the left side.
    static let corner: CGFloat = 14
    /// Beyond this many sessions the expanded list scrolls and the tab shows "+N".
    static let maxVisible = 6

    static let collapsedWidth: CGFloat = 34
    static let collapsedSlot: CGFloat = 30
    static func collapsedHeight(count: Int) -> CGFloat {
        let slots = min(max(count, 1), maxVisible) + (count > maxVisible ? 1 : 0)
        return flare * 2 + 20 + CGFloat(slots) * collapsedSlot
    }

    static let expandedWidth: CGFloat = 340
    static let headerHeight: CGFloat = 44
    static let rowHeight: CGFloat = 76
    static func expandedHeight(count: Int) -> CGFloat {
        flare * 2 + headerHeight + CGFloat(min(max(count, 1), maxVisible)) * rowHeight + 12
    }

    /// Room on the left/top/bottom of the card for its shadow to render.
    static let shadowPadding: CGFloat = 40
}

@MainActor
@Observable
final class PanelState {
    var mode: PanelPresentation.Mode = .hidden
    /// Session ids whose attention request hasn't been seen yet (highlighted rows).
    var pendingAttentionIDs: Set<String> = []
}

/// A borderless, non-activating panel that floats above normal windows on every Space.
final class EdgePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // SwiftUI draws a shape-accurate shadow instead
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class EdgePanelController {
    private let store: SessionStore
    private let state = PanelState()
    private let panel: EdgePanel
    private var presentation = PanelPresentation()
    private var hoverTimer: Timer?
    private var shrinkWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?

    /// Time the pointer has to stay away before collapsing — avoids flicker at the boundary.
    private let collapseDelay: TimeInterval = 0.28
    private var leftAt: Date?
    /// Rows the window is currently sized for. Grows immediately, shrinks after animations settle.
    private var sizedForCount = 1

    init(store: SessionStore) {
        self.store = store
        panel = EdgePanel(contentRect: .zero)

        let root = EdgePanelView(store: store, state: state, onQuit: { NSApp.terminate(nil) })
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        store.onChange = { [weak self] sessions in self?.sessionsChanged(sessions) }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    func show() {
        reposition()
        panel.ignoresMouseEvents = true
        startHoverTracking()
        sessionsChanged(store.sessions)
    }

    // MARK: - Sessions

    private func sessionsChanged(_ sessions: [AgentSession]) {
        let count = sessions.count
        if count > 0 {
            shrinkWork?.cancel()
            if count > sizedForCount {
                sizedForCount = count
                reposition()
            } else if count < sizedForCount {
                // Let the card animate down before shrinking the window around it.
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.sizedForCount = max(self.store.sessions.count, 1)
                    self.reposition()
                }
                shrinkWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
            }
        }

        let hadPending = presentation.pendingAttention
        presentation.update(sessions: sessions)
        let newlyNeedsAttention = !presentation.pendingAttention.subtracting(hadPending).isEmpty
        apply(attentionArrived: newlyNeedsAttention)
    }

    // MARK: - Layout

    private var screen: NSScreen? { NSScreen.main ?? NSScreen.screens.first }

    /// The window is sized for the fully expanded card (plus shadow room) and stays put
    /// while the SwiftUI shape inside animates. That keeps the spring perfectly smooth.
    private func reposition() {
        guard let screen else { return }
        let width = PanelMetrics.expandedWidth + PanelMetrics.shadowPadding
        let height = PanelMetrics.expandedHeight(count: sizedForCount) + PanelMetrics.shadowPadding * 2
        let visible = screen.visibleFrame
        let frame = NSRect(x: screen.frame.maxX - width,
                           y: (visible.midY - height / 2).rounded(),
                           width: width, height: height)
        panel.setFrame(frame, display: true)
    }

    /// Screen-space rect of the visible card, matching EdgePanelView's layout.
    private func cardRect(expanded: Bool) -> NSRect {
        let count = store.sessions.count
        let w = expanded ? PanelMetrics.expandedWidth : PanelMetrics.collapsedWidth
        let h = expanded ? PanelMetrics.expandedHeight(count: count)
                         : PanelMetrics.collapsedHeight(count: count)
        let f = panel.frame
        return NSRect(x: f.maxX - w, y: f.midY - h / 2, width: w, height: h)
    }

    // MARK: - Hover tracking

    /// Polling the pointer is cheap, needs no Accessibility permission, and works
    /// while other apps are frontmost.
    private func startHoverTracking() {
        hoverTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func tick() {
        guard presentation.mode != .hidden else { return }
        let mouse = NSEvent.mouseLocation
        let inside: Bool
        if presentation.mode == .expanded {
            inside = cardRect(expanded: true).insetBy(dx: -16, dy: -16).contains(mouse)
        } else {
            let tab = cardRect(expanded: false)
            let edgeStrip = NSRect(x: tab.maxX - 3, y: tab.minY - 24, width: 3, height: tab.height + 48)
            inside = tab.contains(mouse) || edgeStrip.contains(mouse)
        }

        if inside {
            leftAt = nil
            setHovering(true)
        } else if let leftAt {
            if Date().timeIntervalSince(leftAt) >= collapseDelay { setHovering(false) }
        } else {
            leftAt = Date()
        }
    }

    private func setHovering(_ hovering: Bool) {
        let before = presentation
        presentation.setHovering(hovering)
        guard presentation != before else { return }
        if hovering { leftAt = nil }
        apply(attentionArrived: false)
    }

    // MARK: - Apply

    private func apply(attentionArrived: Bool) {
        let target = presentation.mode
        let pendingIDs = Set(store.sessions.filter {
            $0.attentionKey.map(presentation.pendingAttention.contains) ?? false
        }.map(\.id))
        state.pendingAttentionIDs = pendingIDs

        guard target != state.mode else {
            if attentionArrived { NSSound(named: "Tink")?.play() }
            return
        }
        let previous = state.mode

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animation: Animation
        if reduceMotion {
            animation = .easeOut(duration: 0.18)
        } else {
            switch (previous, target) {
            case (_, .expanded):
                animation = .spring(response: 0.46, dampingFraction: 0.62) // bouncy open
            case (.hidden, .collapsed):
                animation = .spring(response: 0.42, dampingFraction: 0.68) // pops out of the edge
            case (_, .hidden):
                animation = .spring(response: 0.32, dampingFraction: 0.9)
            default:
                animation = .spring(response: 0.34, dampingFraction: 0.86) // tuck away, no bounce
            }
        }

        hideWork?.cancel()
        if target != .hidden, !panel.isVisible { panel.orderFrontRegardless() }

        withAnimation(animation) { state.mode = target }

        // Only accept clicks while open; the collapsed tab and hidden state must not
        // block clicks on whatever is underneath.
        panel.ignoresMouseEvents = target != .expanded

        if target == .hidden {
            leftAt = nil
            let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }

        if attentionArrived {
            NSSound(named: "Tink")?.play()
        } else if target == .expanded {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
