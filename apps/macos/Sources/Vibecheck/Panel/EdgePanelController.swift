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

    // Collapsed tab: one project badge per session.
    static let collapsedWidth: CGFloat = 44
    static let badgeSize: CGFloat = 26
    static let collapsedSlot: CGFloat = badgeSize + 7
    static func collapsedHeight(count: Int) -> CGFloat {
        let slots = min(max(count, 1), maxVisible) + (count > maxVisible ? 1 : 0)
        return flare * 2 + 16 + CGFloat(slots) * collapsedSlot
    }

    static let expandedWidth: CGFloat = 340
    static let headerHeight: CGFloat = 44

    // Session list, grouped by project.
    static let groupHeader: CGFloat = 26
    static let groupPadding: CGFloat = 10      // top + bottom inside a group
    static let groupDivider: CGFloat = 5       // gap between groups (hairline centred)
    static let sessionLine: CGFloat = 24
    static let detailLine: CGFloat = 16
    static let emptyListHeight: CGFloat = 56
    static let maxListHeight: CGFloat = 380

    static func groupHeight(_ group: SessionGroup) -> CGFloat {
        groupHeader + groupPadding + CGFloat(group.sessions.count) * (sessionLine + detailLine)
    }

    static func listContentHeight(_ groups: [SessionGroup]) -> CGFloat {
        guard !groups.isEmpty else { return emptyListHeight }
        return groups.map(groupHeight).reduce(0, +) + CGFloat(groups.count - 1) * groupDivider
    }

    static func listHeight(_ groups: [SessionGroup], hasUsage: Bool) -> CGFloat {
        if groups.isEmpty && hasUsage { return 0 }
        return min(listContentHeight(groups), maxListHeight)
    }

    // Usage section
    static let usageHeaderHeight: CGFloat = 30
    static let usageProviderHeader: CGFloat = 22
    static let usageLine: CGFloat = 20
    static let usageProviderGap: CGFloat = 10
    static let maxUsageHeight: CGFloat = 300

    static func usageHeight(_ usage: [ProviderUsage]) -> CGFloat {
        guard !usage.isEmpty else { return 0 }
        let body = usage.reduce(CGFloat(0)) {
            $0 + usageProviderHeader + CGFloat($1.lineCount) * usageLine + usageProviderGap
        }
        return usageHeaderHeight + min(body, maxUsageHeight)
    }

    static func expandedHeight(groups: [SessionGroup], usage: [ProviderUsage] = []) -> CGFloat {
        flare * 2 + headerHeight + listHeight(groups, hasUsage: !usage.isEmpty) + usageHeight(usage) + 12
    }

    /// The Settings page has a fixed height; its content scrolls.
    static let settingsHeight: CGFloat = 560

    /// Room on the left/top/bottom of the card for its shadow to render.
    static let shadowPadding: CGFloat = 40
}

@MainActor
@Observable
final class PanelState {
    var mode: PanelPresentation.Mode = .hidden
    var page: PanelPage = .sessions
    /// True while a page change is animating, so items use the cascade timing
    /// instead of the expand/collapse timing.
    var pageChanging = false
    /// Session ids whose attention request hasn't been seen yet (highlighted rows).
    var pendingAttentionIDs: Set<String> = []
    var serversOfSessionID: String?
    var editingAction: QuickAction?
    var loggedRun: ActionRunKey?
    var completed = CompletedFilter()
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

/// The panel never activates the app, so AppKit treats the first click on it as a
/// "focus the window" click and SwiftUI drops it. Accepting the first mouse makes
/// every click (session lines, header buttons) act immediately.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class EdgePanelController {
    private let store: SessionStore
    private let usage: UsageStore
    private let servers: DevServerStore
    private let actions: ActionStore
    private let settings: AppSettings
    private let state = PanelState()
    private let panel: EdgePanel
    private var presentation = PanelPresentation()
    private var hoverTimer: Timer?
    private var removalTimer: Timer?
    private var pointerInside = false
    private var shrinkWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var pageSettleWork: DispatchWorkItem?

    /// Time the pointer has to stay away before collapsing — avoids flicker at the boundary.
    private let collapseDelay: TimeInterval = 0.28
    private var leftAt: Date?
    private var lastPointerOverCard: NSPoint?
    /// Height the window is currently sized for. Grows immediately, shrinks after animations settle.
    private var sizedForHeight: CGFloat = 0

    init(store: SessionStore, usage: UsageStore, servers: DevServerStore, actions: ActionStore, diffs: DiffStatsStore,
         settings: AppSettings, updater: AppUpdater?) {
        self.store = store
        self.usage = usage
        self.servers = servers
        self.actions = actions
        self.settings = settings
        panel = EdgePanel(contentRect: .zero)

        let root = EdgePanelView(store: store, usage: usage, servers: servers, actions: actions, diffs: diffs, updater: updater,
                                 state: state,
                                 onSelectTab: { [weak self] in self?.showPage($0) },
                                 onOpenSettings: { [weak self] in self?.showPage(.settings) },
                                 onCloseSettings: { [weak self] in self?.showPage(.sessions) },
                                 onShowAll: { [weak self] in self?.showAllSessions() },
                                 onClearCompleted: { [weak self] in self?.clearCompleted() },
                                 onDismiss: { [weak self] in self?.dismiss($0) },
                                 onShowServers: { [weak self] in self?.showServers(of: $0) },
                                 onEditAction: { [weak self] in self?.editAction($0) },
                                 onSaveAction: { [weak self] in self?.saveAction($0) },
                                 onShowActionLog: { [weak self] in self?.showLog(of: $0) },
                                 onCloseActionPage: { [weak self] in self?.showPage(.actions) },
                                 onQuit: { NSApp.terminate(nil) })
            .environment(settings)
        let hosting = FirstClickHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        store.onChange = { [weak self] sessions in self?.sessionsChanged(sessions) }
        servers.onChange = { [weak self] _ in self?.contentChanged() }
        actions.onChange = { [weak self] in self?.contentChanged() }
        usage.onChange = { [weak self] _ in
            guard let self else { return }
            self.contentChanged()
            self.presentation.setPersistentContent(!self.usage.usage.isEmpty)
            self.apply(attentionArrived: false)
        }

        // Clicking into another app leaves Settings or the action editor. Our own popovers,
        // menus and the folder picker take key too, so only go back when focus left the app.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                DispatchQueue.main.async {
                    guard let self, self.state.page.pinsPanel, NSApp.keyWindow == nil,
                          !self.panel.isKeyWindow else { return }
                    self.showPage(self.state.page == .settings ? .sessions : .actions)
                }
            }
        }

        for (name, tracking) in [(NSMenu.didBeginTrackingNotification, true),
                                 (NSMenu.didEndTrackingNotification, false)] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.presentation.setPinned(tracking || self.state.page.pinsPanel)
                    self.apply(attentionArrived: false)
                }
            }
        }

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
        startRemovalTimer()
        sessionsChanged(store.sessions)
    }

    // MARK: - Pages

    /// Swap the expanded panel's page. Settings pins the panel open so its popovers
    /// and menus (which sit outside the card) don't make it collapse.
    func showPage(_ page: PanelPage) {
        guard page != state.page else { return }
        state.serversOfSessionID = nil
        pageSettleWork?.cancel()
        state.pageChanging = true

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.5, dampingFraction: 0.82)) {
            state.page = page
        }
        contentChanged() // window grows now / shrinks after the cascade, per the new page
        servers.setVisible(page == .servers)
        presentation.setPinned(page.pinsPanel)
        apply(attentionArrived: false)

        if page.pinsPanel {
            panel.makeKey()
            if page == .settings { usage.refreshIfStale() }
        } else if panel.isKeyWindow {
            panel.resignKey()
        }

        let work = DispatchWorkItem { [weak self] in self?.state.pageChanging = false }
        pageSettleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func showServers(of session: AgentSession) {
        showPage(.servers)
        state.serversOfSessionID = session.id
    }

    private func editAction(_ action: QuickAction?) {
        state.editingAction = action ?? QuickAction()
        showPage(.actionEditor)
    }

    private func saveAction(_ action: QuickAction) {
        actions.save(action)
        showPage(.actions)
    }

    private func showLog(of run: ActionRunKey) {
        state.loggedRun = run
        showPage(.actionLog)
    }

    private func clearCompleted() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { state.completed.clear(store.sessions) }
        sessionsChanged(store.sessions)
    }

    private func dismiss(_ session: AgentSession) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { state.completed.dismiss(session) }
        sessionsChanged(store.sessions)
    }

    private func startRemovalTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeFinishedSessions() }
        }
        RunLoop.main.add(timer, forMode: .common)
        removalTimer = timer
    }

    private func removeFinishedSessions() {
        guard !pointerInside, let delay = settings.finishedSessionRemoval.delay else { return }
        var completed = state.completed
        guard completed.clear(store.sessions, finishedBefore: Date.now.addingTimeInterval(-delay)) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { state.completed = completed }
        sessionsChanged(store.sessions)
    }

    private func showAllSessions() {
        presentation.acknowledgeAttention()
        apply(attentionArrived: false)
    }

    // MARK: - Sessions

    private func sessionsChanged(_ sessions: [AgentSession]) {
        contentChanged()
        let hadPending = presentation.pendingAttention
        state.completed.forgetResumed(sessions)
        presentation.update(sessions: sessions, previewCount: state.completed.visible(sessions).count)
        let newlyNeedsAttention = !presentation.pendingAttention.subtracting(hadPending).isEmpty
        apply(attentionArrived: newlyNeedsAttention)
    }

    /// Resize the window for the current content: grow now, shrink once the card has animated down.
    private func contentChanged() {
        let needed = targetHeight
        shrinkWork?.cancel()
        if needed > sizedForHeight {
            sizedForHeight = needed
            reposition()
        } else if needed < sizedForHeight {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.sizedForHeight = self.targetHeight
                self.reposition()
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        }
    }

    private var targetHeight: CGFloat {
        switch state.page {
        case .settings: return PanelMetrics.settingsHeight
        case .actionEditor: return ActionMetrics.editorHeight
        default: break
        }
        let asking = store.sessions.filter { state.pendingAttentionIDs.contains($0.id) }
        if !asking.isEmpty { return QuestionMetrics.pageHeight(asking) }
        switch state.page {
        case .servers: return ServerMetrics.pageHeight(servers.servers.count)
        case .actions: return ActionMetrics.pageHeight(ActionRowItem.all(actions).count)
        case .actionLog: return ActionMetrics.logHeight
        default:
            return PanelMetrics.expandedHeight(groups: ProjectIcons.shared.groups(state.completed.visible(store.sessions)),
                                               usage: usage.usage)
        }
    }

    // MARK: - Layout

    private var screen: NSScreen? { NSScreen.main ?? NSScreen.screens.first }

    /// The window is sized for the fully expanded card (plus shadow room) and stays put
    /// while the SwiftUI shape inside animates. That keeps the spring perfectly smooth.
    private func reposition() {
        guard let screen else { return }
        let width = PanelMetrics.expandedWidth + PanelMetrics.shadowPadding
        let height = max(sizedForHeight, targetHeight) + PanelMetrics.shadowPadding * 2
        let visible = screen.visibleFrame
        let frame = NSRect(x: screen.frame.maxX - width,
                           y: (visible.midY - height / 2).rounded(),
                           width: width, height: height)
        panel.setFrame(frame, display: true)
    }

    /// Screen-space rect of the visible card, matching EdgePanelView's layout.
    private func cardRect(expanded: Bool) -> NSRect {
        let count = state.completed.visible(store.sessions).count
        let w = expanded ? PanelMetrics.expandedWidth : PanelMetrics.collapsedWidth
        let h = expanded ? targetHeight : PanelMetrics.collapsedHeight(count: count)
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

        let stayedPutAfterCardShrank = pointerInside && mouse == lastPointerOverCard
        if inside || stayedPutAfterCardShrank {
            lastPointerOverCard = mouse
            leftAt = nil
            setHovering(true)
        } else if let leftAt {
            if Date().timeIntervalSince(leftAt) >= collapseDelay { setHovering(false) }
        } else {
            leftAt = Date()
        }
    }

    private func setHovering(_ hovering: Bool) {
        pointerInside = hovering
        let before = presentation
        presentation.setHovering(hovering)
        guard presentation != before else { return }
        if hovering { leftAt = nil; usage.refreshIfStale() }
        apply(attentionArrived: false)
    }

    // MARK: - Apply

    private func apply(attentionArrived: Bool) {
        let target = presentation.mode
        let pendingIDs = Set(store.sessions.filter {
            $0.attentionKey.map(presentation.pendingAttention.contains) ?? false
        }.map(\.id))
        if pendingIDs != state.pendingAttentionIDs {
            state.pendingAttentionIDs = pendingIDs
            contentChanged()
        }

        guard target != state.mode else {
            if attentionArrived { NSSound(named: "Tink")?.play() }
            return
        }
        let previous = state.mode
        // Expand/collapse uses its own timing, not the page-change cascade.
        pageSettleWork?.cancel()
        state.pageChanging = false

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
        if target != .expanded && state.page != .sessions {
            state.page = .sessions
            state.serversOfSessionID = nil
            servers.setVisible(false)
            contentChanged()
        }

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
