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
    let state: PanelState
    let onOpenSettings: () -> Void
    let onCloseSettings: () -> Void
    let onShowAll: () -> Void
    let onClearCompleted: () -> Void
    let onQuit: () -> Void
    @Environment(AppSettings.self) private var settings

    private var expanded: Bool { state.mode == .expanded }
    private var hidden: Bool { state.mode == .hidden }
    private var count: Int { store.sessions.count }
    private var preview: [AgentSession] { state.completed.preview(store.sessions) }
    private var onSettings: Bool { state.page == .settings }
    private var groups: [SessionGroup] { ProjectIcons.shared.groups(store.sessions) }
    private var asking: [AgentSession] { store.sessions.filter { state.pendingAttentionIDs.contains($0.id) } }
    private var showsQuestions: Bool { !onSettings && !asking.isEmpty }

    var body: some View {
        let groups = groups
        let width = expanded ? PanelMetrics.expandedWidth : PanelMetrics.collapsedWidth
        let height = expanded ? pageHeight(groups) : PanelMetrics.collapsedHeight(count: preview.count)

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
                                clearableCount: state.completed.clearableCount(store.sessions),
                                pendingIDs: state.pendingAttentionIDs,
                                isShown: expanded && !onSettings && !showsQuestions,
                                hiddenSide: onSettings ? .leading : .trailing,
                                paced: state.pageChanging,
                                onOpenSettings: onOpenSettings, onClearCompleted: onClearCompleted, onQuit: onQuit)
                    .frame(height: PanelMetrics.expandedHeight(groups: groups, usage: usage.usage), alignment: .top)
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

            CollapsedContent(sessions: preview, groups: ProjectIcons.shared.groups(preview))
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
        return PanelMetrics.expandedHeight(groups: groups, usage: usage.usage)
    }
}

// MARK: - Collapsed

/// One project badge per session (most urgent first). The outline carries status;
/// the agent rides as a corner badge.
private struct CollapsedContent: View {
    let sessions: [AgentSession]
    let groups: [SessionGroup]

    var body: some View {
        let ordered = groups.flatMap { g in g.sessions.map { (g.project, $0) } }
        let visible = ordered.prefix(PanelMetrics.maxVisible)
        VStack(spacing: PanelMetrics.collapsedSlot - PanelMetrics.badgeSize) {
            ForEach(visible, id: \.1.id) { project, session in
                SessionBadge(project: project, session: session)
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

    var body: some View {
        let size = PanelMetrics.badgeSize
        ZStack {
            ProjectBadge(project: project, size: size - 6)
            StatusOutline(session: session, size: size)
        }
        .frame(width: size, height: size)
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

/// Rounded-square outline around a project badge: spinning arc while working,
/// breathing for attention, steady otherwise. Color and motion come from `StatusPresentation`.
private struct StatusOutline: View {
    let session: AgentSession
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
        let presentation = StatusPresentation(session)
        let color = presentation.tint.color
        switch presentation.motion {
        case .travel:
            ZStack {
                shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1.6)
                // The arc travels along the outline (the square itself never rotates).
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let start = reduceMotion ? 0 : (t / 1.2).truncatingRemainder(dividingBy: 1)
                    let end = start + 0.28
                    let arc = StrokeStyle(lineWidth: 1.6, lineCap: .round)
                    ZStack {
                        shape.inset(by: 0.8).trim(from: start, to: min(end, 1))
                            .stroke(color, style: arc)
                        if end > 1 {
                            shape.inset(by: 0.8).trim(from: 0, to: end - 1)
                                .stroke(color, style: arc)
                        }
                    }
                }
            }
        case .pulse:
            TimelineView(.animation(paused: reduceMotion)) { context in
                let pulse = reduceMotion ? 1 : (sin(context.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
                shape.strokeBorder(color.opacity(0.45 + 0.55 * pulse), lineWidth: 1.6)
            }
        case .still:
            shape.strokeBorder(color.opacity(0.75), lineWidth: 1.6)
        }
    }
}

struct StatusIndicator: View {
    let session: AgentSession
    var size: CGFloat = 16
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let presentation = StatusPresentation(session)
        let color = presentation.tint.color
        switch session.status {
        case .working:
            LoaderView(style: settings.loader.style(for: session.agent.id), size: size)
        case .needsAttention:
            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let pulse = reduceMotion ? 0 : (sin(t * 4) + 1) / 2
                ZStack {
                    Circle().fill(color.opacity(0.25 * (1 - pulse)))
                        .scaleEffect(0.6 + 0.4 * pulse)
                    Circle().fill(color).frame(width: size * 0.55, height: size * 0.55)
                }
            }
            .frame(width: size, height: size)
        case .idle:
            Image(systemName: session.wasInterrupted ? "stop.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(color)
        case .blocked:
            Image(systemName: "hourglass.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(color)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(color)
        }
    }
}

extension StatusPresentation.Tint {
    var color: Color {
        switch self {
        case .accent: LoaderPalette.accent
        case .attention: .orange
        case .success: .green
        case .muted: Color(white: 0.6)
        case .failure: Color(red: 1, green: 0.42, blue: 0.4)
        }
    }
}

// MARK: - Expanded

private struct ExpandedContent: View {
    let groups: [SessionGroup]
    let sessionCount: Int
    let usage: [ProviderUsage]
    let clearableCount: Int
    let pendingIDs: Set<String>
    /// On screen: panel expanded and the sessions page selected.
    let isShown: Bool
    /// Where items rest while hidden: leading behind Settings, trailing when collapsed.
    let hiddenSide: HorizontalEdge
    let paced: Bool
    let onOpenSettings: () -> Void
    let onClearCompleted: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .cascade(shown: isShown || hiddenSide == .trailing, index: 0, side: hiddenSide, paced: paced)

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
                    .modifier(UsageReveal(shown: isShown, index: min(groups.count, 6) + 1,
                                          side: hiddenSide, paced: paced))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, PanelMetrics.flare)
        .padding(.bottom, PanelMetrics.flare + 6)
    }

    private var waitingCount: Int {
        groups.reduce(0) { $0 + $1.sessions.filter(\.needsAttention).count }
    }

    private var header: some View {
        HStack {
            Text("Agents")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("\(sessionCount)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            if waitingCount > 0 {
                Text("\(waitingCount) waiting")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
            }
            Spacer()
            if clearableCount > 0 {
                HeaderButton(systemImage: "checkmark.circle", label: "Clear completed from the edge tab",
                             action: onClearCompleted)
            }
            HeaderButton(systemImage: "gearshape", label: "Settings", action: onOpenSettings)
            HeaderButton(systemImage: "power", label: "Quit Agent Companion", action: onQuit)
        }
        .frame(height: PanelMetrics.headerHeight)
        .padding(.horizontal, 16)
    }

    private var list: some View {
        VStack(spacing: 0) {
            if groups.isEmpty {
                Text("No agents running")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: PanelMetrics.emptyListHeight)
            }
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                        .padding(.horizontal, 18)
                        .frame(height: PanelMetrics.groupDivider)
                }
                ProjectGroupView(group: group, pendingIDs: pendingIDs)
                    .frame(height: PanelMetrics.groupHeight(group), alignment: .top)
                    // Small stagger so groups settle in after the card lands, and leave
                    // one by one when Settings takes over.
                    .cascade(shown: isShown, index: index + 1, side: hiddenSide, paced: paced)
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

/// Project header (icon, name, agent count) followed by one line per session.
private struct ProjectGroupView: View {
    let group: SessionGroup
    let pendingIDs: Set<String>

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
            .help(Self.abbreviate(group.project.root))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(group.sessions) { session in
                SessionLine(session: session, highlighted: pendingIDs.contains(session.id))
            }
        }
        .padding(.vertical, PanelMetrics.groupPadding / 2)
        .padding(.horizontal, 6)
    }

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// status · agent · title · context · elapsed, then the state and live activity (or the
/// task, when the title is a question). Clicking brings forward the session's app.
private struct SessionLine: View {
    let session: AgentSession
    let highlighted: Bool
    @State private var hovering = false
    @State private var target: JumpTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Same width as the project icon above, so the columns line up:
                // status under the icon, agent under the project name.
                StatusIndicator(session: session, size: 11)
                    .frame(width: 18)
                AgentGlyph(agentID: session.agent.id, size: 12)
                Text(StatusPresentation.headline(session))
                    .font(.system(size: 12))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                if let context = session.context {
                    ContextGauge(usage: context)
                }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(elapsed(now: context.date))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .frame(height: PanelMetrics.sessionLine)

            if let detail = StatusPresentation.detail(session) {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 46) // status 18 + 8 + agent 12 + 8
                    .frame(height: PanelMetrics.detailLine, alignment: .top)
            }
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
        parts.append(ProjectGroupView.abbreviate(session.cwd))
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
