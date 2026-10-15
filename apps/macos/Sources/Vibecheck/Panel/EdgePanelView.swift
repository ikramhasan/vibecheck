import CompanionCore
import SwiftUI

/// The tab silhouette: flush against the right screen edge, convex corners on the left,
/// and concave "flares" top and bottom where it melts into the edge (like the notch).
struct EdgeTabShape: Shape {
    var flare: CGFloat = PanelMetrics.flare
    var corner: CGFloat = PanelMetrics.corner

    func path(in rect: CGRect) -> Path {
        let f = min(flare, rect.height / 4)
        let c = min(corner, (rect.width - f) / 2, (rect.height - 2 * f) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY + f),
                 tangent2End: CGPoint(x: rect.maxX - f, y: rect.minY + f), radius: f)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY + f),
                 tangent2End: CGPoint(x: rect.minX, y: rect.maxY - f), radius: c)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY - f),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - f), radius: c)
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.maxY - f))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY - f),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: f)
        p.closeSubpath()
        return p
    }
}

struct EdgePanelView: View {
    let store: SessionStore
    let usage: UsageStore
    let servers: DevServerStore
    let actions: ActionStore
    let diffs: DiffStatsStore
    let updater: AppUpdater?
    let launchAtLogin: LaunchAtLogin?
    let state: PanelState
    let onSelectTab: (PanelPage) -> Void
    let onOpenSettings: () -> Void
    let onCloseSettings: () -> Void
    let onShowAll: () -> Void
    let onClearCompleted: () -> Void
    let onDismiss: (AgentSession) -> Void
    let onShowServers: (AgentSession) -> Void
    let onShowDiff: (AgentSession) -> Void
    let onEditAction: (QuickAction?) -> Void
    let onSaveAction: (QuickAction) -> Void
    let onShowActionLog: (ActionRunKey) -> Void
    let onCloseActionPage: () -> Void
    let onQuit: () -> Void
    @Environment(AppSettings.self) private var settings

    private var expanded: Bool { state.mode == .expanded }
    private var hidden: Bool { state.mode == .hidden }
    private var shown: [AgentSession] { state.completed.visible(store.sessions) }
    private var count: Int { shown.count }
    private var onSettings: Bool { state.page == .settings }
    private var covered: Bool { state.page.coversTabs }
    private var groups: [SessionGroup] { ProjectIcons.shared.groups(shown) }
    private var asking: [AgentSession] { store.sessions.filter { state.pendingAttentionIDs.contains($0.id) } }
    private var showsQuestions: Bool { !state.page.pinsPanel && !asking.isEmpty }
    private var sessionProjects: [ProjectInfo] { ProjectIcons.shared.groups(store.sessions).map(\.project) }

    var body: some View {
        let groups = groups
        let width = expanded ? PanelMetrics.expandedWidth : PanelMetrics.collapsedWidth
        let height = expanded ? pageHeight(groups) : PanelMetrics.collapsedHeight(count: count, hasUsage: !usage.usage.isEmpty)

        ZStack(alignment: .trailing) {
            Color.clear
            card(groups: groups, width: width, height: height)
                // Hidden = tucked fully past the screen edge.
                .offset(x: hidden ? width + 12 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(groups: [SessionGroup], width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            // Both pages stay mounted so their items can cascade past each other.
            ZStack(alignment: .top) {
                ExpandedContent(groups: groups, sessionCount: count, usage: usage.usage,
                                usageRefreshing: usage.isRefreshing,
                                servers: servers.servers, sessions: store.sessions, actions: actions, diffs: diffs,
                                serversOfSessionID: state.serversOfSessionID,
                                tab: state.page.tab,
                                clearableCount: state.completed.clearableCount(store.sessions),
                                pendingIDs: state.pendingAttentionIDs,
                                isShown: expanded && !covered && !showsQuestions,
                                hiddenSide: covered ? .leading : .trailing,
                                paced: state.pageChanging,
                                onSelectTab: onSelectTab, onOpenSettings: onOpenSettings,
                                onRefreshUsage: usage.refreshAll,
                                onClearCompleted: onClearCompleted, onDismiss: onDismiss,
                                onShowServers: onShowServers, onShowDiff: onShowDiff,
                                onStopServer: servers.stopServer, onEditAction: onEditAction,
                                onShowActionLog: onShowActionLog, onQuit: onQuit)
                    .frame(height: tabHeight(groups), alignment: .top)
                    .environment(\.orbsOnScreen, expanded && state.page == .sessions && !showsQuestions)
                    .opacity(showsQuestions ? 0 : 1)
                    .allowsHitTesting(!covered && !showsQuestions)
                    .accessibilityHidden(covered || showsQuestions)

                ActionEditorPage(editing: state.editingAction, projects: sessionProjects,
                                 isShown: expanded && state.page == .actionEditor, paced: state.pageChanging,
                                 onSave: onSaveAction, onClose: onCloseActionPage)
                    .frame(height: ActionMetrics.editorHeight)
                    .allowsHitTesting(state.page == .actionEditor)
                    .accessibilityHidden(state.page != .actionEditor)

                ActionLogPage(store: actions, runKey: state.loggedRun,
                              isShown: expanded && state.page == .actionLog && !showsQuestions,
                              paced: state.pageChanging, onBack: onCloseActionPage)
                    .frame(height: ActionMetrics.logHeight)
                    .opacity(showsQuestions ? 0 : 1)
                    .allowsHitTesting(state.page == .actionLog && !showsQuestions)
                    .accessibilityHidden(state.page != .actionLog || showsQuestions)

                QuestionPage(sessions: asking, isShown: expanded && showsQuestions, onShowAll: onShowAll)
                    .frame(height: QuestionMetrics.pageHeight(asking), alignment: .top)
                    .allowsHitTesting(showsQuestions)
                    .accessibilityHidden(!showsQuestions)

                SettingsPage(settings: settings, store: store, usage: usage, updater: updater, launchAtLogin: launchAtLogin,
                             isShown: expanded && onSettings, paced: state.pageChanging,
                             onBack: onCloseSettings)
                    .frame(height: PanelMetrics.settingsHeight)
                    .environment(\.orbsOnScreen, expanded && onSettings)
                    .environment(\.orbMaxFPS, 30)
                    .allowsHitTesting(onSettings)
                    .accessibilityHidden(!onSettings)
            }
            .frame(width: PanelMetrics.expandedWidth, height: pageHeight(groups), alignment: .top)
            .opacity(expanded ? 1 : 0)
            .scaleEffect(expanded ? 1 : 0.96, anchor: .trailing)

            CollapsedContent(sessions: shown, groups: groups, servers: servers.servers,
                             usage: usage.usage)
                .frame(width: PanelMetrics.collapsedWidth)
                .environment(\.orbsOnScreen, state.mode == .collapsed)
                .opacity(expanded ? 0 : 1)
        }
        .frame(width: width, height: height, alignment: .trailing)
        .clipShape(EdgeTabShape())
        .glassEffect(.regular, in: EdgeTabShape())
    }

    private func pageHeight(_ groups: [SessionGroup]) -> CGFloat {
        switch state.page {
        case .settings: return PanelMetrics.settingsHeight
        case .actionEditor: return ActionMetrics.editorHeight
        default: break
        }
        if showsQuestions { return QuestionMetrics.pageHeight(asking) }
        if state.page == .actionLog { return ActionMetrics.logHeight }
        return tabHeight(groups)
    }

    private func tabHeight(_ groups: [SessionGroup]) -> CGFloat {
        switch state.page.tab {
        case .servers: ServerMetrics.pageHeight(servers.servers.count)
        case .actions: ActionMetrics.pageHeight(ActionRowItem.all(actions).count)
        default: PanelMetrics.expandedHeight(groups: groups, usage: usage.usage)
        }
    }
}

// MARK: - Collapsed

/// One status orb per session (most urgent first); the agent rides as a corner badge.
private struct CollapsedContent: View {
    let sessions: [AgentSession]
    let groups: [SessionGroup]
    let servers: [DevServer]
    let usage: [ProviderUsage]

    var body: some View {
        let ordered = groups.flatMap { g in g.sessions.map { (g.project, $0) } }
        let visible = ordered.prefix(PanelMetrics.maxVisible)
        GlassEffectContainer(spacing: 4) {
            badges(ordered: ordered, visible: visible)
        }
        .padding(.leading, 3) // optically center between left edge and screen edge
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: ordered.map(\.1.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sessions.isEmpty ? "Agent usage" : accessibilitySummary)
    }

    private func badges(ordered: [(ProjectInfo, AgentSession)],
                        visible: ArraySlice<(ProjectInfo, AgentSession)>) -> some View {
        VStack(spacing: PanelMetrics.collapsedSlot - PanelMetrics.badgeSize) {
            ForEach(visible, id: \.1.id) { project, session in
                SessionBadge(project: project, session: session,
                             runsServer: servers.contains { $0.wasStarted(by: session) })
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
            if ordered.count > visible.count {
                Text("+\(ordered.count - visible.count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(height: PanelMetrics.badgeSize)
            }
            if !usage.isEmpty {
                if !visible.isEmpty {
                    Capsule()
                        .fill(.separator)
                        .frame(width: PanelMetrics.badgeSize * 0.6, height: PanelMetrics.usageDivider)
                }
                UsageDial(usage: usage, size: PanelMetrics.badgeSize)
            }
        }
    }

    private var accessibilitySummary: String {
        let waiting = sessions.filter(\.needsAttention).count
        let base = "\(sessions.count) agent session\(sessions.count == 1 ? "" : "s")"
        return waiting > 0 ? base + ", \(waiting) waiting for you" : base
    }
}

private struct UsageDial: View {
    let usage: [ProviderUsage]
    let size: CGFloat

    private let lineWidth: CGFloat = 3
    private let ringGap: CGFloat = 1.5

    var body: some View {
        let peaks = usage.prefix(3).map { $0.windows.map(\.usedPercent).max() }
        ZStack {
            ForEach(peaks.indices, id: \.self) { index in
                UsageRing(usedPercent: peaks[index], lineWidth: lineWidth)
                    .padding(CGFloat(index) * (lineWidth + ringGap) + lineWidth / 2)
            }
        }
        .frame(width: size, height: size)
        .help(helpText)
    }

    private var helpText: String {
        usage.prefix(3).map { provider in
            let peak = provider.windows.map(\.usedPercent).max()
            return "\(provider.name): " + (peak.map { "\(Int($0.rounded()))%" } ?? "—")
        }.joined(separator: "\n")
    }
}

private struct UsageRing: View {
    let usedPercent: Double?
    let lineWidth: CGFloat

    var body: some View {
        let fraction = min(max((usedPercent ?? 0) / 100, 0), 1)
        let tint = usedPercent.map { UsageTint.color(usedPercent: $0) } ?? .gray
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(AngularGradient(colors: [tint.opacity(0.55), tint],
                                        center: .center,
                                        startAngle: .zero,
                                        endAngle: .degrees(360 * fraction)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .shadow(color: tint.opacity(0.5), radius: 2)
        }
        .rotationEffect(.degrees(-90))
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

private struct SessionBadge: View {
    let project: ProjectInfo
    let session: AgentSession
    let runsServer: Bool

    var body: some View {
        StatusIndicator(session: session, size: PanelMetrics.collapsedOrbSize)
            .frame(width: PanelMetrics.badgeSize, height: PanelMetrics.badgeSize)
            .overlay(alignment: .topTrailing) {
                if runsServer {
                    PromptGlyph(size: 7, lineWidth: 1.3)
                        .foregroundStyle(.primary)
                        .frame(width: 13, height: 13)
                        .glassEffect(.regular, in: .circle)
                        .offset(x: 4, y: -4)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                AgentGlyph(agentID: session.agent.id, size: 13)
                    .offset(x: 4, y: 4)
            }
            .help("\(session.agent.name) · \(project.name)")
    }
}

struct StatusIndicator: View {
    let session: AgentSession
    var size: CGFloat = 16
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let presentation = StatusPresentation(session)
        Orb(look: look(presentation.orb), face: BuddyFace(session), seed: session.id, size: size,
            color: presentation.tint.color,
            animated: presentation.orb != .resting)
            .environment(\.orbFamily, settings.orbFamily)
    }

    private func look(_ orb: StatusPresentation.Orb) -> OrbLook {
        switch orb {
        case .working: OrbLook(settings.loader.style(for: session.agent.id), seed: session.id)
        case .waiting: .waiting
        case .retrying: .retrying
        case .resting: .base
        }
    }
}

extension StatusPresentation.Tint {
    var color: Color {
        switch self {
        case .accent: .blue
        case .attention: .orange
        case .success: .green
        case .muted: .gray
        case .limited: .yellow
        case .failure: .red
        }
    }
}

// MARK: - Expanded

private struct ExpandedContent: View {
    let groups: [SessionGroup]
    let sessionCount: Int
    let usage: [ProviderUsage]
    let usageRefreshing: Bool
    let servers: [DevServer]
    let sessions: [AgentSession]
    let actions: ActionStore
    let diffs: DiffStatsStore
    let serversOfSessionID: String?
    let tab: PanelPage
    let clearableCount: Int
    let pendingIDs: Set<String>
    /// On screen: panel expanded and the sessions page selected.
    let isShown: Bool
    /// Where items rest while hidden: leading behind Settings, trailing when collapsed.
    let hiddenSide: HorizontalEdge
    let paced: Bool
    let onSelectTab: (PanelPage) -> Void
    let onOpenSettings: () -> Void
    let onRefreshUsage: () -> Void
    let onClearCompleted: () -> Void
    let onDismiss: (AgentSession) -> Void
    let onShowServers: (AgentSession) -> Void
    let onShowDiff: (AgentSession) -> Void
    let onStopServer: (DevServer) -> Void
    let onEditAction: (QuickAction?) -> Void
    let onShowActionLog: (ActionRunKey) -> Void
    let onQuit: () -> Void

    @Namespace private var glass

    private var onSessions: Bool { tab == .sessions }
    private var onServers: Bool { tab == .servers }
    private var onActions: Bool { tab == .actions }
    private var sessionsShown: Bool { isShown && onSessions }
    private var sessionsSide: HorizontalEdge { onSessions ? hiddenSide : .leading }
    private var serversSide: HorizontalEdge {
        switch tab {
        case .servers: hiddenSide
        case .actions: .leading
        default: .trailing
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .cascade(shown: isShown || hiddenSide == .trailing, index: 0, side: hiddenSide, paced: paced)

            ZStack(alignment: .top) {
                sessionsSection
                    .allowsHitTesting(onSessions)
                    .accessibilityHidden(!onSessions)
                serverSection
                    .allowsHitTesting(onServers)
                    .accessibilityHidden(!onServers)
                actionSection
                    .allowsHitTesting(onActions)
                    .accessibilityHidden(!onActions)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, PanelMetrics.flare)
        .padding(.bottom, PanelMetrics.flare + 6)
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            let listHeight = PanelMetrics.listHeight(groups, hasUsage: !usage.isEmpty)
            if listHeight > 0 {
                if PanelMetrics.listContentHeight(groups) > PanelMetrics.maxListHeight {
                    ScrollView(.vertical) { list }
                        .scrollIndicators(.never)
                        .frame(height: listHeight)
                } else {
                    list.frame(height: listHeight, alignment: .top)
                }
            }
            if !usage.isEmpty {
                UsageSection(usage: usage, isRefreshing: usageRefreshing, onRefresh: onRefreshUsage)
                    .frame(height: PanelMetrics.usageHeight(usage), alignment: .top)
                    .modifier(UsageReveal(shown: sessionsShown, index: min(groups.count, 6) + 1,
                                          side: sessionsSide, paced: paced))
            }
        }
    }

    private var serverSection: some View {
        let list = ServerList(servers: servers, sessions: sessions, highlightedSessionID: serversOfSessionID, shown: isShown && onServers,
                              side: serversSide, paced: paced, onStop: onStopServer)
        return Group {
            if ServerMetrics.listContentHeight(servers.count) > PanelMetrics.maxListHeight {
                ScrollView(.vertical) { list }
                    .scrollIndicators(.never)
            } else {
                list
            }
        }
        .frame(height: ServerMetrics.listHeight(servers.count), alignment: .top)
    }

    private var actionSection: some View {
        let rowCount = ActionRowItem.all(actions).count
        let list = ActionList(store: actions, shown: isShown && onActions, side: onActions ? hiddenSide : .trailing, paced: paced,
                              onNew: { onEditAction(nil) }, onEdit: onEditAction, onShowLog: onShowActionLog)
        return Group {
            if ActionMetrics.listContentHeight(rowCount) > PanelMetrics.maxListHeight {
                ScrollView(.vertical) { list }
                    .scrollIndicators(.never)
            } else {
                list
            }
        }
        .frame(height: ActionMetrics.listHeight(rowCount), alignment: .top)
    }

    private var waitingCount: Int {
        groups.reduce(0) { $0 + $1.sessions.filter(\.needsAttention).count }
    }

    private var header: some View {
        HStack(spacing: 2) {
            TabButton(title: "Agents", count: sessionCount, waiting: waitingCount, selected: onSessions,
                      namespace: glass) {
                onSelectTab(.sessions)
            }
            TabButton(title: "Servers", count: servers.count, selected: onServers, namespace: glass) {
                onSelectTab(.servers)
            }
            TabButton(title: "Actions", systemImage: "bolt.fill",
                      count: actions.running.isEmpty ? nil : actions.running.count,
                      selected: onActions, namespace: glass) {
                onSelectTab(.actions)
            }
            Spacer()
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    if clearableCount > 0 && onSessions {
                        HeaderButton(systemImage: "checkmark", label: "Clear completed from the edge tab",
                                     action: onClearCompleted)
                            .glassEffectID("clear", in: glass)
                    }
                    HeaderButton(systemImage: "gearshape", label: "Settings", action: onOpenSettings)
                        .glassEffectID("settings", in: glass)
                    HeaderButton(systemImage: "power", label: "Quit vibecheck", action: onQuit)
                        .glassEffectID("quit", in: glass)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: clearableCount > 0 && onSessions)
        }
        .frame(height: PanelMetrics.headerHeight)
        .padding(.horizontal, 10)
    }

    private var list: some View {
        VStack(spacing: 0) {
            if groups.isEmpty {
                Text("No agents running")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: PanelMetrics.emptyListHeight)
                    .cascade(shown: sessionsShown, index: 1, side: sessionsSide, paced: paced)
            }
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Rectangle().fill(.separator).frame(height: 1)
                        .padding(.horizontal, 18)
                        .frame(height: PanelMetrics.groupDivider)
                        .cascade(shown: sessionsShown, index: index, side: sessionsSide, paced: paced)
                }
                ProjectGroupView(group: group, pendingIDs: pendingIDs, servers: servers, actions: actions, diffs: diffs,
                                 onDismiss: onDismiss, onShowServers: onShowServers, onShowDiff: onShowDiff,
                                 onShowActionLog: onShowActionLog)
                    .frame(height: PanelMetrics.groupHeight(group), alignment: .top)
                    // Small stagger so groups settle in after the card lands, and leave
                    // one by one when Settings takes over.
                    .cascade(shown: sessionsShown, index: index + 1, side: sessionsSide, paced: paced)
            }
        }
    }
}

private struct HeaderButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? HierarchicalShapeStyle.primary : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct TabButton: View {
    let title: String
    var systemImage: String?
    let count: Int?
    var waiting = 0
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .frame(height: 28)
                .background {
                    if selected {
                        Color.clear
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .matchedGeometryEffect(id: "tabSelection", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(systemImage == nil ? "" : title)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var tint: HierarchicalShapeStyle { selected ? .primary : hovering ? .secondary : .tertiary }

    @ViewBuilder private var label: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
                .overlay(alignment: .topTrailing) {
                    if let count {
                        Text("\(count)")
                            .font(.system(size: 8.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3.5)
                            .frame(minWidth: 13, minHeight: 13)
                            .background(Capsule().fill(Color.blue))
                            .offset(x: 1, y: -1)
                    }
                }
        } else {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                if waiting > 0 {
                    Text("\(waiting) waiting")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                } else if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(selected ? HierarchicalShapeStyle.secondary : .tertiary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(.quinary))
                }
            }
            .fixedSize()
            .padding(.horizontal, 6)
        }
    }

    private var accessibilityText: String {
        let counted = count.map { "\(title), \($0)" } ?? title
        return waiting > 0 ? "\(counted), \(waiting) waiting" : counted
    }
}

private struct CircleButton<Icon: View>: View {
    static var size: CGFloat { 20 }
    static var spacing: CGFloat { 4 }

    let label: String
    let help: String
    let action: () -> Void
    @ViewBuilder let icon: Icon
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            icon
                .foregroundStyle(hovering ? HierarchicalShapeStyle.primary : .secondary)
                .frame(width: Self.size, height: Self.size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(help)
        .accessibilityLabel(label)
    }
}

/// Project header (icon, name, agent count) followed by one line per session.
private struct ProjectGroupView: View {
    let group: SessionGroup
    let pendingIDs: Set<String>
    let servers: [DevServer]
    let actions: ActionStore
    let diffs: DiffStatsStore
    let onDismiss: (AgentSession) -> Void
    let onShowServers: (AgentSession) -> Void
    let onShowDiff: (AgentSession) -> Void
    let onShowActionLog: (ActionRunKey) -> Void

    private var projectActions: [QuickAction] {
        actions.actions.filter { ProjectIcons.shared.project(for: $0.directory).root == group.project.root }
    }

    var body: some View {
        let projectActions = projectActions
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProjectBadge(project: group.project, size: 18)
                Text(group.project.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let host = group.project.host {
                    HStack(spacing: 3) {
                        Image(systemName: "network")
                        Text(host)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
                if group.sessions.count > 1 {
                    Text("\(group.sessions.count) agents")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: PanelMetrics.groupHeader)
            .padding(.horizontal, 12)
            .help(ProjectPath.abbreviate(group.project.root))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(group.sessions) { session in
                SessionLine(session: session, highlighted: pendingIDs.contains(session.id),
                            servers: servers.filter { $0.wasStarted(by: session) },
                            projectActions: projectActions,
                            diff: diffs.stats(for: session),
                            diffSharedWith: diffs.sessionsSharingCheckout(with: session),
                            actionRun: { actions.run(for: $0, in: directory(of: $0, for: session)) },
                            onDismiss: { onDismiss(session) }, onShowServers: { onShowServers(session) },
                            onShowDiff: { onShowDiff(session) },
                            onAction: { trigger($0, for: session) },
                            onResetDiff: { diffs.resetBaseline(of: session) })
            }
        }
        .padding(.vertical, PanelMetrics.groupPadding / 2)
        .padding(.horizontal, 6)
    }

    private func directory(of action: QuickAction, for session: AgentSession) -> String {
        let resolver = ProjectIcons.shared.resolver
        return resolver.path(action.directory, inCheckout: resolver.checkout(for: session.cwd))
    }

    private func trigger(_ action: QuickAction, for session: AgentSession) {
        let directory = directory(of: action, for: session)
        if actions.run(for: action, in: directory)?.isRunning == true {
            onShowActionLog(ActionRunKey(actionID: action.id, directory: directory))
        } else {
            actions.run(action, in: directory)
        }
    }
}

/// status · title, then the state and live activity (or the task, when the title is a
/// question) with agent · context · elapsed at the end. Clicking brings forward the session's app.
private struct SessionLine: View {
    let session: AgentSession
    let highlighted: Bool
    let servers: [DevServer]
    let projectActions: [QuickAction]
    let diff: DiffStats?
    let diffSharedWith: Int
    let actionRun: (QuickAction) -> ActionRun?
    let onDismiss: () -> Void
    let onShowServers: () -> Void
    let onShowDiff: () -> Void
    let onAction: (QuickAction) -> Void
    let onResetDiff: () -> Void
    @State private var hovering = false
    @State private var target: JumpTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Same width as the project icon above, so the columns line up:
                // status under the icon, title under the project name.
                StatusIndicator(session: session, size: 18)
                Text(StatusPresentation.headline(session))
                    .font(.system(size: 12))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if !showsActions {
                    HStack(spacing: 8) {
                        if let context = session.context {
                            ContextGauge(usage: context)
                        }
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(elapsed(now: context.date))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .fixedSize()
                    .transition(.opacity)
                }
            }
            .padding(.trailing, showsActions ? actionsWidth + 6 : 0)
            .frame(height: PanelMetrics.sessionLine)

            HStack(spacing: 8) {
                if let detail = StatusPresentation.detail(session) {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    AgentGlyph(agentID: session.agent.id, size: 12)
                    if let diff {
                        DiffBadge(stats: diff, sharedWith: diffSharedWith)
                    }
                }
                .fixedSize()
                .opacity(showsActions ? 0 : 1)
            }
            .padding(.leading, 26) // status 18 + 8
            .frame(height: PanelMetrics.detailLine, alignment: .top)
        }
        .overlay(alignment: .trailing) {
            if showsActions { actions.transition(.opacity) }
        }
        .padding(.horizontal, 12)
        .glassEffect(rowGlass, in: .rect(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { h in
            if h, target == nil {
                let session = session
                Task { target = await Task.detached(priority: .utility) { SessionJumper.target(for: session) }.value }
            }
            withAnimation(.easeOut(duration: 0.12)) { hovering = h }
        }
        .onTapGesture { SessionJumper.jump(to: session) }
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(target.map { "Opens \($0.appName)" } ?? "Opens the app this session is running in")
        .accessibilityAction { SessionJumper.jump(to: session) }
        .accessibilityAction(named: "Dismiss") { if dismissible { onDismiss() } }
        .accessibilityAction(named: "Show servers") { if !servers.isEmpty { onShowServers() } }
        .accessibilityAction(named: "Show changes") { if canShowDiff { onShowDiff() } }
        .accessibilityAction(named: Self.resetDiffLabel) { if canResetDiff { onResetDiff() } }
        .accessibilityActions {
            ForEach(projectActions) { action in
                Button(label(for: action)) { onAction(action) }
            }
        }
    }

    private var rowGlass: Glass {
        if highlighted { return .regular.tint(.orange.opacity(0.3)).interactive() }
        return hovering ? .regular.interactive() : .identity
    }

    private var dismissible: Bool { CompletedFilter.isCompleted(session) }
    private var canResetDiff: Bool { diff?.baselineLeftHistory == true }
    private var canShowDiff: Bool { (diff?.files ?? 0) > 0 }
    private static let resetDiffLabel = "Count changes from here"
    private var actionCount: Int {
        (servers.isEmpty ? 0 : 1) + (projectActions.isEmpty ? 0 : 1) + (dismissible ? 1 : 0) + (canResetDiff ? 1 : 0)
            + (canShowDiff ? 1 : 0)
    }
    private var anyActionRunning: Bool { projectActions.contains { actionRun($0)?.isRunning == true } }

    private func label(for action: QuickAction) -> String {
        actionRun(action)?.isRunning == true ? "Show output of \(action.name)" : "Run \(action.name)"
    }

    @ViewBuilder private var actionIcon: some View {
        if anyActionRunning {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: projectActions.count == 1 ? "play.fill" : "bolt.fill")
                .font(.system(size: 8.5, weight: .bold))
        }
    }
    private var showsActions: Bool { hovering && actionCount > 0 }

    private var actionsWidth: CGFloat {
        CGFloat(actionCount) * CircleButton<EmptyView>.size + CGFloat(actionCount - 1) * CircleButton<EmptyView>.spacing
    }

    private var actions: some View {
        GlassEffectContainer(spacing: CircleButton<EmptyView>.spacing) {
            actionButtons
        }
    }

    private var actionButtons: some View {
        HStack(spacing: CircleButton<EmptyView>.spacing) {
            if canShowDiff {
                CircleButton(label: "Show changes", help: "Show changes", action: onShowDiff) {
                    Image(systemName: "plus.forwardslash.minus").font(.system(size: 9, weight: .bold))
                }
            }
            if canResetDiff {
                CircleButton(label: Self.resetDiffLabel,
                             help: "The branch changed since this session started. Count its changes from the current commit.",
                             action: onResetDiff) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 9, weight: .bold))
                }
            }
            if !servers.isEmpty {
                CircleButton(label: "Show servers",
                             help: (["Show servers"] + servers.map(\.summary)).joined(separator: "\n"),
                             action: onShowServers) {
                    PromptGlyph(size: 9, lineWidth: 1.4)
                }
            }
            if projectActions.count == 1, let action = projectActions.first {
                CircleButton(label: label(for: action), help: label(for: action), action: { onAction(action) }) {
                    actionIcon
                }
            } else if !projectActions.isEmpty {
                Menu {
                    ForEach(projectActions) { action in
                        Button(label(for: action)) { onAction(action) }
                    }
                } label: {
                    actionIcon
                        .foregroundStyle(.secondary)
                        .frame(width: CircleButton<EmptyView>.size, height: CircleButton<EmptyView>.size)
                        .contentShape(Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .glassEffect(.regular.interactive(), in: .circle)
                .help("Actions")
                .accessibilityLabel("Actions")
            }
            if dismissible {
                CircleButton(label: "Dismiss", help: "Dismiss", action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
            }
        }
    }

    private var titleColor: Color {
        switch session.status {
        case .needsAttention: .orange
        case .error, .working, .blocked: Color.primary.opacity(0.9)
        case .idle: session.task == nil ? Color.primary.opacity(0.45) : Color.primary.opacity(0.62)
        }
    }

    private func elapsed(now: Date) -> String {
        let since = session.statusSince ?? session.updatedAt
        let text = ElapsedFormat.short(since: since, now: now)
        return session.status == .idle && text != "now" ? text + " ago" : text
    }

    private var tooltip: String {
        var parts = ["\(session.agent.name)\(session.model.map { " · \($0)" } ?? "")"]
        parts.append([StatusPresentation(session).word, session.activity].compactMap { $0 }.joined(separator: " · "))
        if session.status == .needsAttention { parts.append(StatusPresentation.task(session)) }
        if let context = session.context { parts.append(ContextGauge.summary(context)) }
        if !servers.isEmpty {
            parts.append("Running " + servers.map(\.summary).joined(separator: ", "))
        }
        if let diff { parts += DiffSummary.lines(diff, sharedWith: diffSharedWith) }
        parts.append((session.host.map { "\($0):" } ?? "") + ProjectPath.abbreviate(session.cwd))
        if let app = target?.appName { parts.append("Click to open \(app)") }
        return parts.joined(separator: "\n")
    }

    private var accessibilityText: String {
        let detail = StatusPresentation.detail(session).map { ". \($0)" } ?? ""
        return "\(session.agent.name), \(StatusPresentation(session).word): \(StatusPresentation.headline(session))\(detail)"
    }
}

private struct DiffBadge: View {
    let stats: DiffStats
    let sharedWith: Int

    var body: some View {
        HStack(spacing: 3) {
            if stats.baselineLeftHistory {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.orange)
            }
            if stats.files > 0 {
                if stats.added + stats.removed == 0 {
                    Text(stats.files == 1 ? "1 file" : "\(stats.files) files").foregroundStyle(.tertiary)
                } else {
                    Text("+\(DiffSummary.count(stats.added))").foregroundStyle(.green.opacity(0.85))
                    Text("−\(DiffSummary.count(stats.removed))").foregroundStyle(.red.opacity(0.8))
                }
            }
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .help(DiffSummary.lines(stats, sharedWith: sharedWith).joined(separator: "\n"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DiffSummary.lines(stats, sharedWith: sharedWith).joined(separator: ". "))
    }
}

private struct ContextGauge: View {
    let usage: AgentSession.ContextUsage

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1.6)
            Circle().trim(from: 0, to: min(usage.fraction, 1))
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 9, height: 9)
        .help(Self.summary(usage))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context \(Int((usage.fraction * 100).rounded())) percent full")
    }

    private var color: Color {
        switch usage.level {
        case .normal: Color.primary.opacity(0.5)
        case .warning: .orange
        case .critical: .red
        }
    }

    static func summary(_ usage: AgentSession.ContextUsage) -> String {
        let percent = Int((usage.fraction * 100).rounded())
        let text = "Context \(percent)% full · \(tokens(usage.usedTokens)) / \(tokens(usage.windowTokens)) tokens"
        return usage.level == .critical ? text + " · Auto-compact likely soon" : text
    }

    private static func tokens(_ count: Int) -> String {
        count >= 1_000_000 ? String(format: "%.1fM", Double(count) / 1_000_000) : "\(count / 1000)k"
    }
}

/// Usage fades in on expand (as before), but cascades like a row on a page change.
private struct UsageReveal: ViewModifier {
    let shown: Bool
    let index: Int
    let side: HorizontalEdge
    let paced: Bool

    func body(content: Content) -> some View {
        if paced {
            content.cascade(shown: shown, index: index, side: side)
        } else {
            content
                .opacity(shown ? 1 : 0)
                .animation(shown ? .easeOut(duration: 0.25).delay(0.12) : .easeOut(duration: 0.1), value: shown)
        }
    }
}
