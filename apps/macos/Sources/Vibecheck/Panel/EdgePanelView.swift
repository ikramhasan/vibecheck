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
    let state: PanelState
    let onSelectTab: (PanelPage) -> Void
    let onOpenSettings: () -> Void
    let onCloseSettings: () -> Void
    let onShowAll: () -> Void
    let onClearCompleted: () -> Void
    let onDismiss: (AgentSession) -> Void
    let onShowServers: (AgentSession) -> Void
    let onQuit: () -> Void
    @Environment(AppSettings.self) private var settings

    private var expanded: Bool { state.mode == .expanded }
    private var hidden: Bool { state.mode == .hidden }
    private var shown: [AgentSession] { state.completed.visible(store.sessions) }
    private var count: Int { shown.count }
    private var onSettings: Bool { state.page == .settings }
    private var onServers: Bool { state.page == .servers }
    private var groups: [SessionGroup] { ProjectIcons.shared.groups(shown) }
    private var asking: [AgentSession] { store.sessions.filter { state.pendingAttentionIDs.contains($0.id) } }
    private var showsQuestions: Bool { !onSettings && !asking.isEmpty }

    var body: some View {
        let groups = groups
        let width = expanded ? PanelMetrics.expandedWidth : PanelMetrics.collapsedWidth
        let height = expanded ? pageHeight(groups) : PanelMetrics.collapsedHeight(count: count)

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
                                servers: servers.servers, sessions: store.sessions,
                                serversOfSessionID: state.serversOfSessionID,
                                tab: onServers ? .servers : .sessions,
                                clearableCount: state.completed.clearableCount(store.sessions),
                                pendingIDs: state.pendingAttentionIDs,
                                isShown: expanded && !onSettings && !showsQuestions,
                                hiddenSide: onSettings ? .leading : .trailing,
                                paced: state.pageChanging,
                                onSelectTab: onSelectTab, onOpenSettings: onOpenSettings,
                                onClearCompleted: onClearCompleted, onDismiss: onDismiss,
                                onShowServers: onShowServers,
                                onStopServer: servers.stopServer, onQuit: onQuit)
                    .frame(height: onServers ? ServerMetrics.pageHeight(servers.servers.count)
                           : PanelMetrics.expandedHeight(groups: groups, usage: usage.usage), alignment: .top)
                    .opacity(showsQuestions ? 0 : 1)
                    .allowsHitTesting(!onSettings && !showsQuestions)
                    .accessibilityHidden(onSettings || showsQuestions)

                QuestionPage(sessions: asking, isShown: expanded && showsQuestions, onShowAll: onShowAll)
                    .frame(height: QuestionMetrics.pageHeight(asking), alignment: .top)
                    .allowsHitTesting(showsQuestions)
                    .accessibilityHidden(!showsQuestions)

                SettingsPage(settings: settings, store: store, usage: usage,
                             isShown: expanded && onSettings, paced: state.pageChanging,
                             onBack: onCloseSettings)
                    .frame(height: PanelMetrics.settingsHeight)
                    .allowsHitTesting(onSettings)
                    .accessibilityHidden(!onSettings)
            }
            .frame(width: PanelMetrics.expandedWidth, height: pageHeight(groups), alignment: .top)
            .opacity(expanded ? 1 : 0)
            .blur(radius: expanded ? 0 : 6)
            .scaleEffect(expanded ? 1 : 0.96, anchor: .trailing)

            CollapsedContent(sessions: shown, groups: groups, servers: servers.servers)
                .frame(width: PanelMetrics.collapsedWidth)
                .opacity(expanded ? 0 : 1)
                .blur(radius: expanded ? 4 : 0)
        }
        .frame(width: width, height: height, alignment: .trailing)
        .clipShape(EdgeTabShape())
        .background {
            EdgeTabShape()
                .fill(Color(white: 0.055))
                .shadow(color: .black.opacity(expanded ? 0.45 : 0.25),
                        radius: expanded ? 24 : 8, x: -2, y: expanded ? 10 : 2)
        }
        .overlay {
            EdgeTabShape().stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func pageHeight(_ groups: [SessionGroup]) -> CGFloat {
        if onSettings { return PanelMetrics.settingsHeight }
        if showsQuestions { return QuestionMetrics.pageHeight(asking) }
        if onServers { return ServerMetrics.pageHeight(servers.servers.count) }
        return PanelMetrics.expandedHeight(groups: groups, usage: usage.usage)
    }
}

// MARK: - Collapsed

/// One status orb per session (most urgent first); the agent rides as a corner badge.
private struct CollapsedContent: View {
    let sessions: [AgentSession]
    let groups: [SessionGroup]
    let servers: [DevServer]

    var body: some View {
        let ordered = groups.flatMap { g in g.sessions.map { (g.project, $0) } }
        let visible = ordered.prefix(PanelMetrics.maxVisible)
        VStack(spacing: PanelMetrics.collapsedSlot - PanelMetrics.badgeSize) {
            ForEach(visible, id: \.1.id) { project, session in
                SessionBadge(project: project, session: session,
                             runsServer: servers.contains { $0.wasStarted(by: session) })
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
            if sessions.isEmpty {
                // Only usage to show: a quiet gauge so the tab still reads as something.
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(height: PanelMetrics.badgeSize)
            }
            if ordered.count > visible.count {
                Text("+\(ordered.count - visible.count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(height: PanelMetrics.badgeSize)
            }
        }
        .padding(.leading, 3) // optically center between left edge and screen edge
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: ordered.map(\.1.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sessions.isEmpty ? "Agent usage" : accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let waiting = sessions.filter(\.needsAttention).count
        let base = "\(sessions.count) agent session\(sessions.count == 1 ? "" : "s")"
        return waiting > 0 ? base + ", \(waiting) waiting for you" : base
    }
}

private struct SessionBadge: View {
    let project: ProjectInfo
    let session: AgentSession
    let runsServer: Bool

    var body: some View {
        StatusIndicator(session: session, size: PanelMetrics.badgeSize)
            .overlay(alignment: .topTrailing) {
                if runsServer {
                    PromptGlyph(size: 7, lineWidth: 1.3)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 13, height: 13)
                        .background(Circle().fill(Color(white: 0.11)))
                        .overlay(Circle().strokeBorder(Color(white: 0.055), lineWidth: 1.5))
                        .offset(x: 4, y: -4)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                AgentGlyph(agentID: session.agent.id, size: 8)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(Color(white: 0.11)))
                    .overlay(Circle().strokeBorder(Color(white: 0.055), lineWidth: 1.5))
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
        Orb(look: look(presentation.orb), size: size, color: presentation.tint.color,
            animated: presentation.orb != .resting)
    }

    private func look(_ orb: StatusPresentation.Orb) -> OrbLook {
        switch orb {
        case .working: OrbLook(settings.loader.style(for: session.agent.id))
        case .waiting: .waiting
        case .retrying: .retrying
        case .resting: .base
        }
    }
}

extension StatusPresentation.Tint {
    var color: Color {
        switch self {
        case .accent: Color(red: 0.32, green: 0.56, blue: 1.0)
        case .attention: .orange
        case .success: .green
        case .muted: Color(white: 0.6)
        case .limited: Color(red: 1, green: 0.84, blue: 0.3)
        case .failure: Color(red: 1, green: 0.42, blue: 0.4)
        }
    }
}

// MARK: - Expanded

private struct ExpandedContent: View {
    let groups: [SessionGroup]
    let sessionCount: Int
    let usage: [ProviderUsage]
    let servers: [DevServer]
    let sessions: [AgentSession]
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
    let onClearCompleted: () -> Void
    let onDismiss: (AgentSession) -> Void
    let onShowServers: (AgentSession) -> Void
    let onStopServer: (DevServer) -> Void
    let onQuit: () -> Void

    private var onServers: Bool { tab == .servers }
    private var sessionsShown: Bool { isShown && !onServers }
    private var sessionsSide: HorizontalEdge { onServers ? .leading : hiddenSide }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .cascade(shown: isShown || hiddenSide == .trailing, index: 0, side: hiddenSide, paced: paced)

            ZStack(alignment: .top) {
                sessionsSection
                    .allowsHitTesting(!onServers)
                    .accessibilityHidden(onServers)
                serverSection
                    .allowsHitTesting(onServers)
                    .accessibilityHidden(!onServers)
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
                UsageSection(usage: usage)
                    .frame(height: PanelMetrics.usageHeight(usage), alignment: .top)
                    .modifier(UsageReveal(shown: sessionsShown, index: min(groups.count, 6) + 1,
                                          side: sessionsSide, paced: paced))
            }
        }
    }

    private var serverSection: some View {
        let list = ServerList(servers: servers, sessions: sessions, highlightedSessionID: serversOfSessionID, shown: isShown && onServers,
                              side: onServers ? hiddenSide : .trailing, paced: paced, onStop: onStopServer)
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

    private var waitingCount: Int {
        groups.reduce(0) { $0 + $1.sessions.filter(\.needsAttention).count }
    }

    private var header: some View {
        HStack(spacing: 4) {
            TabButton(title: "Agents", count: sessionCount, waiting: waitingCount, selected: !onServers) {
                onSelectTab(.sessions)
            }
            TabButton(title: "Servers", count: servers.count, selected: onServers) { onSelectTab(.servers) }
            Spacer()
            if clearableCount > 0 && !onServers {
                HeaderButton(systemImage: "checkmark.circle", label: "Clear completed from the edge tab",
                             action: onClearCompleted)
            }
            HeaderButton(systemImage: "gearshape", label: "Settings", action: onOpenSettings)
            HeaderButton(systemImage: "power", label: "Quit vibecheck", action: onQuit)
        }
        .frame(height: PanelMetrics.headerHeight)
        .padding(.leading, 10)
        .padding(.trailing, 16)
    }

    private var list: some View {
        VStack(spacing: 0) {
            if groups.isEmpty {
                Text("No agents running")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: PanelMetrics.emptyListHeight)
                    .cascade(shown: sessionsShown, index: 1, side: sessionsSide, paced: paced)
            }
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                        .padding(.horizontal, 18)
                        .frame(height: PanelMetrics.groupDivider)
                        .cascade(shown: sessionsShown, index: index, side: sessionsSide, paced: paced)
                }
                ProjectGroupView(group: group, pendingIDs: pendingIDs, servers: servers, onDismiss: onDismiss,
                                 onShowServers: onShowServers)
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
                .foregroundStyle(.white.opacity(hovering ? 0.85 : 0.45))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(hovering ? 0.06 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct TabButton: View {
    let title: String
    let count: Int
    var waiting = 0
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(selected ? 1 : hovering ? 0.7 : 0.42))
                if waiting > 0 {
                    Text("\(waiting) waiting")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                } else {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(selected ? 0.5 : 0.35))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(selected ? 0.08 : 0.05)))
                }
            }
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(hovering && !selected ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .accessibilityLabel(waiting > 0 ? "\(title), \(count), \(waiting) waiting" : "\(title), \(count)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct CircleButton<Icon: View>: View {
    static var size: CGFloat { 18 }
    static var spacing: CGFloat { 4 }

    let label: String
    let help: String
    let action: () -> Void
    @ViewBuilder let icon: Icon
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            icon
                .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.5))
                .frame(width: Self.size, height: Self.size)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.14 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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
    let onDismiss: (AgentSession) -> Void
    let onShowServers: (AgentSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProjectBadge(project: group.project, size: 18)
                Text(group.project.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if group.sessions.count > 1 {
                    Text("\(group.sessions.count) agents")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.32))
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
                            onDismiss: { onDismiss(session) }, onShowServers: { onShowServers(session) })
            }
        }
        .padding(.vertical, PanelMetrics.groupPadding / 2)
        .padding(.horizontal, 6)
    }
}

/// status · title, then the state and live activity (or the task, when the title is a
/// question) with agent · context · elapsed at the end. Clicking brings forward the session's app.
private struct SessionLine: View {
    let session: AgentSession
    let highlighted: Bool
    let servers: [DevServer]
    let onDismiss: () -> Void
    let onShowServers: () -> Void
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
            }
            .padding(.trailing, showsActions ? actionsWidth + 6 : 0)
            .frame(height: PanelMetrics.sessionLine)

            HStack(spacing: 8) {
                if let detail = StatusPresentation.detail(session) {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    AgentGlyph(agentID: session.agent.id, size: 12)
                    if let context = session.context {
                        ContextGauge(usage: context)
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(elapsed(now: context.date))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }
                .opacity(showsActions ? 0 : 1)
            }
            .padding(.leading, 26) // status 18 + 8
            .frame(height: PanelMetrics.detailLine, alignment: .top)
        }
        .overlay(alignment: .trailing) {
            if showsActions { actions.transition(.opacity) }
        }
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(highlighted ? Color.orange.opacity(0.1) : Color.white.opacity(hovering ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { h in
            // Resolve lazily: walking the process tree per render would be wasteful.
            if h { target = SessionJumper.target(for: session) }
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
    }

    private var dismissible: Bool { CompletedFilter.isCompleted(session) }
    private var actionCount: Int { (servers.isEmpty ? 0 : 1) + (dismissible ? 1 : 0) }
    private var showsActions: Bool { hovering && actionCount > 0 }

    private var actionsWidth: CGFloat {
        CGFloat(actionCount) * CircleButton<EmptyView>.size + CGFloat(actionCount - 1) * CircleButton<EmptyView>.spacing
    }

    private var actions: some View {
        HStack(spacing: CircleButton<EmptyView>.spacing) {
            if !servers.isEmpty {
                CircleButton(label: "Show servers",
                             help: (["Show servers"] + servers.map(\.summary)).joined(separator: "\n"),
                             action: onShowServers) {
                    PromptGlyph(size: 9, lineWidth: 1.4)
                }
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
        case .needsAttention: Color(red: 1, green: 0.82, blue: 0.54)
        case .error, .working, .blocked: .white.opacity(0.9)
        case .idle: session.task == nil ? .white.opacity(0.45) : .white.opacity(0.62)
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
        parts.append(ProjectPath.abbreviate(session.cwd))
        if let app = target?.appName { parts.append("Click to open \(app)") }
        return parts.joined(separator: "\n")
    }

    private var accessibilityText: String {
        let detail = StatusPresentation.detail(session).map { ". \($0)" } ?? ""
        return "\(session.agent.name), \(StatusPresentation(session).word): \(StatusPresentation.headline(session))\(detail)"
    }
}

private struct ContextGauge: View {
    let usage: AgentSession.ContextUsage

    var body: some View {
        HStack(spacing: 3) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 1.6)
                Circle().trim(from: 0, to: min(usage.fraction, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 9, height: 9)
            Text("\(Int((usage.fraction * 100).rounded()))%")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(usage.level == .normal ? .white.opacity(0.38) : color)
        }
        .help(Self.summary(usage))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context \(Int((usage.fraction * 100).rounded())) percent full")
    }

    private var color: Color {
        switch usage.level {
        case .normal: .white.opacity(0.5)
        case .warning: .orange
        case .critical: Color(red: 1, green: 0.42, blue: 0.4)
        }
    }

    static func summary(_ usage: AgentSession.ContextUsage) -> String {
        let text = "\(tokens(usage.usedTokens)) / \(tokens(usage.windowTokens)) tokens"
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
