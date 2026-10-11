import CompanionCore
import SwiftUI

/// Compact usage block under the session list: one group per enabled provider with a
/// bar per quota window (5h, weekly, …), reset countdown, and local cost estimate.
struct UsageSection: View {
    let usage: [ProviderUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Usage")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.4)
                .frame(maxWidth: .infinity, minHeight: PanelMetrics.usageHeaderHeight,
                       maxHeight: PanelMetrics.usageHeaderHeight, alignment: .bottomLeading)
                .padding(.horizontal, 18)
                // Full-width hairline, matching the dividers between project groups.
                .overlay(alignment: .top) {
                    Rectangle().fill(.separator).frame(height: 1).padding(.horizontal, 18)
                }

            let content = VStack(alignment: .leading, spacing: PanelMetrics.usageProviderGap) {
                ForEach(usage) { ProviderUsageView(usage: $0) }
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

private struct ProviderUsageView: View {
    let usage: ProviderUsage

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
                if let cost = usage.cost {
                    CostLabel(cost: cost)
                }
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
                    ForEach(usage.windows, id: \.label) { WindowRow(window: $0) }
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
    let window: UsageWindow

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
                .lineLimit(1)

            UsageBar(fraction: window.usedPercent / 100, tint: tint)
                .frame(height: 4)

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
        .frame(height: PanelMetrics.usageLine)
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(helpText)
    }

    private var tint: Color {
        switch window.usedPercent {
        case ..<75: .green
        case ..<90: .orange
        default: .red
        }
    }

    private var helpText: String {
        var s = "\(window.label): \(Int(window.usedPercent.rounded()))% used"
        if let r = window.resetsAt {
            s += ", resets \(r.formatted(date: .abbreviated, time: .shortened))"
        }
        return s
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

private struct CostLabel: View {
    let cost: CostSummary

    var body: some View {
        HStack(spacing: 4) {
            if let today = cost.todayUSD {
                Text(Self.money(today))
                    .foregroundStyle(.primary)
                Text("today").foregroundStyle(.tertiary)
            }
            if cost.todayUSD != nil, cost.periodUSD != nil {
                Text("·").foregroundStyle(.quaternary)
            }
            if let period = cost.periodUSD {
                Text(Self.money(period))
                    .foregroundStyle(.secondary)
                Text("30d").foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .help("Estimated at API list prices from local session logs (\(cost.periodLabel ?? "last 30 days")).")
    }

    static func money(_ v: Double) -> String {
        v >= 100 ? "$\(Int(v.rounded()))" : String(format: "$%.2f", v)
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
