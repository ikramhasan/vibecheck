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
    let state: PanelState
    let onQuit: () -> Void

    private var expanded: Bool { state.mode == .expanded }
    private var hidden: Bool { state.mode == .hidden }
    private var count: Int { store.sessions.count }

    var body: some View {
        let width = expanded ? PanelMetrics.expandedWidth : PanelMetrics.collapsedWidth
        let height = expanded ? PanelMetrics.expandedHeight(count: count)
                              : PanelMetrics.collapsedHeight(count: count)

        ZStack(alignment: .trailing) {
            Color.clear
            card(width: width, height: height)
                // Hidden = tucked fully past the screen edge.
                .offset(x: hidden ? width + 12 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            ExpandedContent(sessions: store.sessions, pendingIDs: state.pendingAttentionIDs,
                            isExpanded: expanded, onQuit: onQuit)
                .frame(width: PanelMetrics.expandedWidth,
                       height: PanelMetrics.expandedHeight(count: count))
                .opacity(expanded ? 1 : 0)
                .blur(radius: expanded ? 0 : 6)
                .scaleEffect(expanded ? 1 : 0.96, anchor: .trailing)

            CollapsedContent(sessions: store.sessions)
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
}

// MARK: - Collapsed

private struct CollapsedContent: View {
    let sessions: [AgentSession]

    var body: some View {
        let visible = sessions.prefix(PanelMetrics.maxVisible)
        VStack(spacing: PanelMetrics.collapsedSlot - 20) {
            ForEach(visible) { session in
                StatusIndicator(status: session.status, size: 16)
                    .frame(height: 20)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
            if sessions.count > visible.count {
                Text("+\(sessions.count - visible.count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(height: 20)
            }
        }
        .padding(.leading, 4) // optically center between left edge and screen edge
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: sessions.map(\.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sessions.count) agent sessions")
    }
}

struct StatusIndicator: View {
    let status: AgentSession.Status
    var size: CGFloat = 16

    var body: some View {
        switch status {
        case .working:
            // Clock-driven so it never joins the expand/collapse spring transaction.
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: 0.32)
                        .stroke(Color(red: 0.32, green: 0.56, blue: 1.0),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360))
                }
            }
            .frame(width: size, height: size)
        case .needsAttention:
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let pulse = (sin(t * 4) + 1) / 2
                ZStack {
                    Circle().fill(Color.orange.opacity(0.25 * (1 - pulse)))
                        .scaleEffect(0.6 + 0.4 * pulse)
                    Circle().fill(Color.orange).frame(width: size * 0.55, height: size * 0.55)
                }
            }
            .frame(width: size, height: size)
        case .idle:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Expanded

private struct ExpandedContent: View {
    let sessions: [AgentSession]
    let pendingIDs: Set<String>
    let isExpanded: Bool
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Agents")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(sessions.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                Spacer()
                Button(action: onQuit) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Quit Agent Companion")
                .accessibilityLabel("Quit Agent Companion")
            }
            .frame(height: PanelMetrics.headerHeight)
            .padding(.horizontal, 16)

            if sessions.count > PanelMetrics.maxVisible {
                ScrollView(.vertical) { rows }
                    .scrollIndicators(.never)
            } else {
                rows
            }
            Spacer(minLength: 0)
        }
        .padding(.top, PanelMetrics.flare)
        .padding(.bottom, PanelMetrics.flare + 6)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                SessionRow(session: session, highlighted: pendingIDs.contains(session.id))
                    .frame(height: PanelMetrics.rowHeight)
                    // Small stagger so rows settle in after the card lands.
                    .offset(x: isExpanded ? 0 : 24)
                    .opacity(isExpanded ? 1 : 0)
                    .animation(
                        isExpanded
                            ? .spring(response: 0.5, dampingFraction: 0.7).delay(0.04 + Double(min(index, 6)) * 0.04)
                            : .easeOut(duration: 0.12),
                        value: isExpanded)
            }
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let highlighted: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusIndicator(status: session.status, size: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    AgentGlyph(agentID: session.agent.id)
                    Text(session.name ?? session.agent.name)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Text("·").foregroundStyle(.white.opacity(0.3))
                    Text(Self.abbreviate(session.cwd))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .font(.system(size: 11, weight: .medium))

                Text(session.task ?? "New session")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(session.task == nil ? .white.opacity(0.5) : .white)
                    .lineLimit(1)

                Text(statusLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(highlighted ? Color.orange.opacity(0.12)
                                  : Color.white.opacity(hovering ? 0.06 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(highlighted ? 0.35 : 0), lineWidth: 1)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(session.attention?.message ?? session.task ?? "")
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        switch session.status {
        case .working: "✻ \(session.activity ?? "Working…")"
        case .needsAttention: "? \(session.attention?.message ?? "Needs your attention")"
        case .idle: session.activity.map { "✓ \($0)" } ?? "✓ Waiting for your next prompt"
        case .error: "✕ \(session.activity ?? "Run failed")"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .working: Color(red: 0.8, green: 0.55, blue: 0.4)
        case .needsAttention: .orange
        case .idle: .white.opacity(0.5)
        case .error: Color(red: 1, green: 0.45, blue: 0.45)
        }
    }

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
