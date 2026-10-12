import AppKit
import CompanionCore
import SwiftUI

enum ServerMetrics {
    static let line: CGFloat = 24
    static let detailLine: CGFloat = 16
    static let row: CGFloat = line + detailLine + 6
    static let listPadding: CGFloat = 8

    static func listContentHeight(_ count: Int) -> CGFloat {
        count == 0 ? PanelMetrics.emptyListHeight : CGFloat(count) * row + listPadding
    }

    static func listHeight(_ count: Int) -> CGFloat {
        min(listContentHeight(count), PanelMetrics.maxListHeight)
    }

    static func pageHeight(_ count: Int) -> CGFloat {
        PanelMetrics.flare * 2 + PanelMetrics.headerHeight + listHeight(count) + 12
    }
}

struct ServerList: View {
    let servers: [DevServer]
    let sessions: [AgentSession]
    let highlightedSessionID: String?
    let shown: Bool
    let side: HorizontalEdge
    let paced: Bool
    let onStop: (DevServer) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if servers.isEmpty {
                Text("No dev servers running")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: PanelMetrics.emptyListHeight)
                    .cascade(shown: shown, index: 1, side: side, paced: paced)
            }
            ForEach(Array(servers.enumerated()), id: \.element.id) { index, server in
                let session = sessions.first(where: server.wasStarted(by:))
                ServerRow(server: server, session: session,
                          highlighted: session.map { $0.id == highlightedSessionID } ?? false,
                          onStop: { onStop(server) })
                    .frame(height: ServerMetrics.row)
                    .cascade(shown: shown, index: index + 1, side: side, paced: paced)
            }
        }
        .padding(.vertical, ServerMetrics.listPadding / 2)
        .padding(.horizontal, 6)
    }
}

private struct ServerRow: View {
    let server: DevServer
    let session: AgentSession?
    let highlighted: Bool
    let onStop: () -> Void
    @State private var hovering = false
    @State private var confirmingStop = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ServerIcon(server: server, size: 16)
                    .frame(width: 18)
                Text(server.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(server.address ?? server.framework.displayName)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                trailing
            }
            .frame(height: ServerMetrics.line)

            HStack(spacing: 5) {
                if let session {
                    AgentGlyph(agentID: session.agent.id, size: 10)
                }
                Text(projectLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, 26)
            .frame(height: ServerMetrics.detailLine, alignment: .top)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .glassEffect(rowGlass, in: .rect(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) {
                hovering = h
                if !h { confirmingStop = false }
            }
        }
        .onTapGesture(perform: open)
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(server.url != nil ? "Opens it in your browser" : server.remote == nil ? "Brings the app forward" : "")
        .accessibilityAction(.default) { open() }
        .accessibilityActions {
            if server.url != nil { Button("Copy URL") { copy() } }
            if revealPath != nil { Button("Reveal in Finder") { reveal() } }
            if server.canStop { Button(server.appPath == nil ? "Stop" : "Quit") { onStop() } }
        }
    }

    private var accessibilityText: String {
        "\(server.summary), \(projectLabel)"
    }

    private var rowGlass: Glass {
        if highlighted { return .regular.tint(.orange.opacity(0.3)).interactive() }
        return hovering ? .regular.interactive() : .identity
    }

    @ViewBuilder private var trailing: some View {
        if hovering {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    if server.url != nil {
                        RowAction(systemImage: copied ? "checkmark" : "doc.on.doc", label: "Copy URL", action: copy)
                    }
                    if revealPath != nil {
                        RowAction(systemImage: "folder", label: server.appPath == nil ? "Reveal project in Finder"
                                  : "Reveal app in Finder", action: reveal)
                    }
                    if server.url != nil || server.remote == nil {
                        RowAction(systemImage: "arrow.up.right",
                                  label: server.url == nil ? "Bring to front" : "Open in browser", action: open)
                    }
                    if server.canStop { stopButton }
                }
            }
            .transition(.opacity)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(ElapsedFormat.short(since: server.startedAt, now: context.date))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private var stopButton: some View {
        if confirmingStop {
            Button {
                confirmingStop = false
                onStop()
            } label: {
                Text("Stop")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.red).interactive(), in: .capsule)
            .help(server.appPath == nil ? "Click again to stop this server" : "Click again to quit this app")
            .accessibilityLabel("Confirm stop")
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            RowAction(systemImage: "stop.fill", label: server.appPath == nil ? "Stop" : "Quit") {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { confirmingStop = true }
            }
        }
    }

    private var projectLabel: String {
        guard let cwd = server.cwd else { return server.framework == .docker ? "Container" : "Unknown folder" }
        if let remote = server.remote { return "\(URL(fileURLWithPath: cwd).lastPathComponent) · \(remote.host)" }
        let project = ProjectIcons.shared.project(for: cwd)
        guard cwd.hasPrefix(project.root + "/") else { return project.name }
        return project.name + cwd.dropFirst(project.root.count)
    }

    private var tooltip: String {
        let host = server.remote?.host ?? "localhost"
        var lines = server.ports.isEmpty ? [] : [server.ports.map { "\(host):\($0)" }.joined(separator: ", ")]
        if let path = server.appPath ?? server.cwd {
            lines.append(server.remote == nil ? ProjectPath.abbreviate(path) : "\(host):\(path)")
        }
        if let remote = server.remote, server.url == nil {
            lines.append(remote.loopbackOnly ? "Only reachable on \(host) itself: it listens on localhost there"
                : "This Mac's address for \(host) is unknown")
        }
        if let session { lines.append("Started by \(session.agent.name): \(StatusPresentation.headline(session))") }
        if server.hostsAgent { lines.append("Runs an agent session, so it can't be quit from here") }
        if server.url != nil {
            lines.append("Click to open in your browser")
        } else if server.remote == nil {
            lines.append("Click to bring it to the front")
        }
        return lines.joined(separator: "\n")
    }

    private var revealPath: String? { server.remote == nil ? server.appPath ?? server.cwd : nil }

    private func open() {
        if let url = server.url {
            NSWorkspace.shared.open(url)
        } else if server.remote == nil {
            NSRunningApplication(processIdentifier: server.pid)?.activate()
        }
    }

    private func copy() {
        guard let url = server.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        withAnimation(.easeOut(duration: 0.12)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.12)) { copied = false }
        }
    }

    private func reveal() {
        guard let revealPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: revealPath)])
    }
}

struct RowAction: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(hovering ? HierarchicalShapeStyle.primary : .secondary)
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(label)
        .accessibilityLabel(label)
    }
}

enum ProjectPath {
    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
