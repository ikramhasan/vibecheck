import AppKit
import CompanionCore
import ImageIO
import SwiftUI

struct OnboardingPreview: View {
    let settings: AppSettings
    @State private var expanded = false
    @State private var cursor = CursorSpot.away

    var body: some View {
        let sessions = PreviewSessions.make(agents: sessionAgents, hosts: settings.remoteHosts)
        let groups = SessionGroup.make(sessions) { ProjectInfo(root: $0, name: ($0 as NSString).lastPathComponent) }
        let usage = PreviewUsage.make(agents: usageAgents)
        GeometryReader { geo in
            let scale = min(1, (geo.size.height - 56) / PanelMetrics.expandedHeight(groups: groups, usage: usage))
            ZStack(alignment: .trailing) {
                Wallpaper()
                PreviewPanel(sessions: sessions, groups: groups, usage: usage, expanded: expanded)
                    .scaleEffect(scale, anchor: .trailing)
                    .animation(.spring(response: 0.42, dampingFraction: 0.8), value: sessions.map(\.id))
                    .animation(.spring(response: 0.42, dampingFraction: 0.8), value: usage.map(\.id))
                Image(nsImage: NSCursor.arrow.image)
                    .position(cursor.point(in: geo.size, scale: scale))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topLeading) {
            Label("Live preview", systemImage: "eye")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .capsule)
                .padding(14)
        }
        .allowsHitTesting(false)
        .task { await loop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live preview of the panel")
    }

    private var chosenAgents: [OnboardingAgent] {
        let chosen = OnboardingAgent.all.filter { settings.agents.observes($0) }
        return chosen.isEmpty ? OnboardingAgent.all : chosen
    }

    private var sessionAgents: [AgentSession.AgentInfo] {
        let chosen = chosenAgents.filter(\.reportsSessions)
        let agents = chosen.isEmpty ? OnboardingAgent.all.filter(\.reportsSessions) : chosen
        return agents.map { .init(id: $0.id, name: $0.name) }
    }

    private var usageAgents: [OnboardingAgent] { chosenAgents.filter(\.reportsUsage) }

    private func loop() async {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            expanded = true
            cursor = .hidden
            return
        }
        while !Task.isCancelled {
            await step(after: 1.2) { withAnimation(.easeInOut(duration: 0.9)) { cursor = .tab } }
            await step(after: 1.0) {
                withAnimation(.spring(response: 0.46, dampingFraction: 0.62)) { expanded = true }
                withAnimation(.easeInOut(duration: 0.7)) { cursor = .row }
            }
            await step(after: 3.6) { withAnimation(.easeInOut(duration: 0.8)) { cursor = .away } }
            await step(after: 0.45) { withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { expanded = false } }
        }
    }

    private func step(after seconds: Double, _ change: () -> Void) async {
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled else { return }
        change()
    }
}

private enum CursorSpot {
    case away, tab, row, hidden

    func point(in size: CGSize, scale: CGFloat) -> CGPoint {
        switch self {
        case .away: CGPoint(x: size.width * 0.3, y: size.height * 0.62)
        case .tab: CGPoint(x: size.width - PanelMetrics.collapsedWidth * scale * 0.45, y: size.height * 0.5 + 6)
        case .row: CGPoint(x: size.width - PanelMetrics.expandedWidth * scale * 0.55, y: size.height * 0.5 + 10)
        case .hidden: CGPoint(x: -40, y: -40)
        }
    }
}

private enum PreviewSessions {
    private static let start = Date.now

    static func make(agents: [AgentSession.AgentInfo], hosts: [RemoteHost]) -> [AgentSession] {
        let samples = [
            AgentSession(agent: agents[0], sessionID: "preview-1", cwd: "/preview/shop-web", status: .working,
                         task: "Add Stripe checkout to pricing page", activity: "Running npm test",
                         context: .init(usedTokens: 96_000, windowTokens: 200_000), updatedAt: start.addingTimeInterval(-540)),
            AgentSession(agent: agents[1 % agents.count], sessionID: "preview-2", cwd: "/preview/shop-web",
                         status: .needsAttention, task: "Migrate auth middleware to edge runtime",
                         attention: .init(kind: .question, message: "Which runtime should the middleware target?"),
                         updatedAt: start.addingTimeInterval(-60)),
            AgentSession(agent: agents[2 % agents.count], sessionID: "preview-3", cwd: "/preview/notes-app",
                         status: .working, task: "Redesign the settings window", activity: "Editing SettingsView.swift",
                         updatedAt: start.addingTimeInterval(-240)),
            AgentSession(agent: agents[0], sessionID: "preview-4", cwd: "/preview/notes-app", status: .blocked,
                         task: "Write the release notes", activity: "Usage limit reached",
                         updatedAt: start.addingTimeInterval(-900)),
            AgentSession(agent: agents[1 % agents.count], sessionID: "preview-5", cwd: "/preview/cli", status: .idle,
                         task: "Fix flaky snapshot test",
                         lastReply: "Fixed it. The snapshot depended on the time zone, so I pinned it to UTC.",
                         updatedAt: start.addingTimeInterval(-90)),
        ]
        let remote = hosts.prefix(2).enumerated().map { index, host in
            var session = AgentSession(agent: agents[index % agents.count], sessionID: "preview-remote-\(index)",
                                       cwd: "/home/dev/api", status: .working, task: "Profile slow database queries",
                                       activity: "Running pytest", updatedAt: start.addingTimeInterval(-180))
            session.host = host.alias
            return session
        }
        return samples + remote
    }
}

private enum PreviewUsage {
    private static let start = Date.now

    static func make(agents: [OnboardingAgent]) -> [ProviderUsage] {
        agents.compactMap { agent in
            let windows: [(String, Double, TimeInterval)]
            let name: String
            let plan: String
            switch agent.id {
            case "claude": (name, plan, windows) = ("Claude", "Max 5x", [("5h", 37, 3.6 * 3600), ("Weekly", 82, 6 * 86400)])
            case "codex": (name, plan, windows) = ("Codex", "Plus", [("5h", 12, 2.2 * 3600), ("Weekly", 41, 3 * 86400)])
            case "kiro": (name, plan, windows) = ("Kiro", "Power", [("Monthly", 68, 19 * 86400)])
            default: return nil
            }
            return ProviderUsage(id: agent.id, name: name, state: .loaded, plan: plan,
                                 windows: windows.map { UsageWindow(label: $0.0, usedPercent: $0.1,
                                                                    resetsAt: start.addingTimeInterval($0.2)) })
        }
    }
}

private struct PreviewPanel: View {
    let sessions: [AgentSession]
    let groups: [SessionGroup]
    let usage: [ProviderUsage]
    let expanded: Bool

    var body: some View {
        let expandedHeight = PanelMetrics.expandedHeight(groups: groups, usage: usage)
        ZStack(alignment: .trailing) {
            PreviewCard(groups: groups, usage: usage)
                .frame(width: PanelMetrics.expandedWidth, height: expandedHeight, alignment: .top)
                .opacity(expanded ? 1 : 0)
                .scaleEffect(expanded ? 1 : 0.96, anchor: .trailing)

            CollapsedContent(sessions: sessions, groups: groups, servers: [], usage: usage)
                .frame(width: PanelMetrics.collapsedWidth)
                .opacity(expanded ? 0 : 1)
        }
        .frame(width: expanded ? PanelMetrics.expandedWidth : PanelMetrics.collapsedWidth,
               height: expanded ? expandedHeight
                   : PanelMetrics.collapsedHeight(count: sessions.count, hasUsage: !usage.isEmpty),
               alignment: .trailing)
        .clipShape(EdgeTabShape())
        .glassEffect(.regular, in: EdgeTabShape())
    }
}

private struct PreviewCard: View {
    let groups: [SessionGroup]
    let usage: [ProviderUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Agents")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(groups.reduce(0) { $0 + $1.sessions.count })")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .glassEffect(.regular, in: .circle)
            }
            .frame(height: PanelMetrics.headerHeight)
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Rectangle().fill(.separator).frame(height: 1)
                            .padding(.horizontal, 18)
                            .padding(.vertical, (PanelMetrics.groupDivider - 1) / 2)
                    }
                    PreviewGroup(group: group)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(height: PanelMetrics.listHeight(groups, hasUsage: !usage.isEmpty), alignment: .top)
            .clipped()

            if !usage.isEmpty {
                UsageSection(usage: usage, isRefreshing: false, onRefresh: {})
                    .frame(height: PanelMetrics.usageHeight(usage), alignment: .top)
                    .transition(.opacity)
            }
        }
        .padding(.top, PanelMetrics.flare)
        .padding(.bottom, PanelMetrics.flare + 6)
    }
}

private struct PreviewGroup: View {
    let group: SessionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProjectBadge(project: group.project, size: 18)
                Text(group.project.name)
                    .font(.system(size: 12.5, weight: .semibold))
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

            ForEach(group.sessions) { PreviewLine(session: $0) }
        }
        .padding(.vertical, PanelMetrics.groupPadding / 2)
        .padding(.horizontal, 6)
    }
}

private struct PreviewLine: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StatusIndicator(session: session, size: 18)
                Text(StatusPresentation.headline(session))
                    .font(.system(size: 12))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let context = session.context { ContextGauge(usage: context) }
                Text(elapsed)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(height: PanelMetrics.sessionLine)

            HStack(spacing: 8) {
                if let detail = StatusPresentation.detail(session) {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                AgentGlyph(agentID: session.agent.id, size: 12)
            }
            .padding(.leading, 26)
            .frame(height: PanelMetrics.detailLine, alignment: .top)
        }
        .padding(.horizontal, 12)
        .glassEffect(session.needsAttention ? .regular.tint(.orange.opacity(0.3)) : .identity,
                     in: .rect(cornerRadius: 12, style: .continuous))
    }

    private var titleColor: Color {
        switch session.status {
        case .needsAttention: .orange
        case .idle: Color.primary.opacity(0.62)
        default: Color.primary.opacity(0.9)
        }
    }

    private var elapsed: String {
        let text = ElapsedFormat.short(since: session.updatedAt)
        return session.status == .idle ? text + " ago" : text
    }
}

private struct Wallpaper: View {
    @State private var image: NSImage?

    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(alignment: .trailing) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
            .clipped()
            .allowsHitTesting(false)
        .task {
            let wallpaper = await DesktopWallpaper.load()
            withAnimation(.easeOut(duration: 0.3)) { image = wallpaper.map { NSImage(cgImage: $0, size: .zero) } }
        }
        .accessibilityHidden(true)
    }
}

private enum DesktopWallpaper {
    private static let systemDefault = URL(filePath: "/System/Library/Desktop Pictures/Sonoma.heic")

    static func load() async -> CGImage? {
        let current = NSScreen.main.flatMap(NSWorkspace.shared.desktopImageURL(for:))
        return await Task.detached(priority: .userInitiated) {
            [current, systemDefault].compactMap { $0 }.lazy.compactMap(downsampled).first
        }.value
    }

    private static func downsampled(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 1800] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
