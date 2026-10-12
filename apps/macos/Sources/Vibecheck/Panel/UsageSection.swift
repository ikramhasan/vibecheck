import CompanionCore
import SwiftUI

/// Compact usage block under the session list: one group per enabled provider with a
/// bar per quota window (5h, weekly, …) and its reset countdown.
struct UsageSection: View {
    let usage: [ProviderUsage]
    let isRefreshing: Bool
    let onRefresh: () -> Void

    private var widestLabel: String {
        usage.flatMap(\.windows).map(\.label).max { $0.count < $1.count } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 6) {
                Text("Usage")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer(minLength: 0)
                Text("% used")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .help("Bars and percentages show how much of each limit is used")
                RefreshButton(isRefreshing: isRefreshing, action: onRefresh)
            }
            .frame(maxWidth: .infinity, minHeight: PanelMetrics.usageHeaderHeight,
                   maxHeight: PanelMetrics.usageHeaderHeight, alignment: .bottomLeading)
            .padding(.horizontal, 18)
            // Full-width hairline, matching the dividers between project groups.
            .overlay(alignment: .top) {
                Rectangle().fill(.separator).frame(height: 1).padding(.horizontal, 18)
            }

            let content = VStack(alignment: .leading, spacing: PanelMetrics.usageProviderGap) {
                ForEach(usage) { ProviderUsageView(usage: $0, widestLabel: widestLabel) }
            }
            .padding(.top, 6)
            .padding(.horizontal, 18)

            if PanelMetrics.usageHeight(usage) - PanelMetrics.usageHeaderHeight >= PanelMetrics.maxUsageHeight {
                ScrollView(.vertical) { content }.scrollIndicators(.never)
            } else {
                content
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Usage")
    }
}

private struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? HierarchicalShapeStyle.secondary : .tertiary)
                .symbolEffect(.rotate, isActive: isRefreshing)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(isRefreshing ? "Refreshing usage…" : "Refresh usage")
        .accessibilityLabel("Refresh usage")
    }
}

private struct ProviderUsageView: View {
    let usage: ProviderUsage
    let widestLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                AgentGlyph(agentID: usage.id)
                Text(usage.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let plan = shortPlan {
                    Text(plan)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.quinary))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .frame(height: PanelMetrics.usageProviderHeader)

            switch usage.state {
            case .loading where usage.windows.isEmpty:
                message("Loading…", color: Color.primary.opacity(0.4))
            case .failed(let error) where usage.windows.isEmpty:
                message(error, color: .red)
                    .help(error)
            default:
                if usage.windows.isEmpty {
                    message("No quota reported", color: Color.primary.opacity(0.4))
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 0) {
                        GridRow {
                            Text(widestLabel)
                                .font(WindowRow.labelFont)
                                .fixedSize()
                                .frame(minWidth: 50, alignment: .leading)
                                .frame(height: 0)
                                .hidden()
                        }
                        ForEach(usage.windows, id: \.label) { WindowRow(window: $0) }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Claude Pro" under Claude reads as just "Pro".
    private var shortPlan: String? {
        guard var plan = usage.plan, !plan.isEmpty else { return nil }
        if plan.lowercased().hasPrefix(usage.name.lowercased() + " ") {
            plan = String(plan.dropFirst(usage.name.count + 1))
        }
        return plan
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: PanelMetrics.usageLine, alignment: .leading)
    }
}

private struct WindowRow: View {
    static let labelFont = Font.system(size: 11, weight: .medium)
    let window: UsageWindow

    var body: some View {
        GridRow {
            Text(window.label)
                .font(Self.labelFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 50, minHeight: PanelMetrics.usageLine, alignment: .leading)
                .help(helpText)

            UsageBar(fraction: window.usedPercent / 100, tint: tint)
                .frame(height: 4)
                .frame(maxWidth: .infinity)
                .help(helpText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(helpText)

            Text("\(Int(window.usedPercent.rounded()))%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: 34, alignment: .trailing)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(window.resetsAt.map { ResetFormat.countdown(to: $0, now: context.date) } ?? "—")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 56, alignment: .trailing)
        }
    }

    private var tint: Color { UsageTint.color(usedPercent: window.usedPercent) }

    private var helpText: String {
        var s = "\(window.label): \(Int(window.usedPercent.rounded()))% used"
        if let r = window.resetsAt {
            s += ", resets \(r.formatted(date: .abbreviated, time: .shortened))"
        }
        return s
    }
}

enum UsageTint {
    static func color(usedPercent: Double) -> Color {
        switch usedPercent {
        case ..<75: .green
        case ..<90: .orange
        default: .red
        }
    }
}

private struct UsageBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quinary)
                Capsule().fill(tint)
                    .frame(width: max(fraction > 0 ? 4 : 0, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

enum ResetFormat {
    /// "42m", "3h 36m", "6d 1h".
    static func countdown(to date: Date, now: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}
