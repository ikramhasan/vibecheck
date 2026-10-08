import Foundation

/// A provider CodexBar knows about (`codexbar config providers`). Its `id` doubles as
/// the agent id used by session integrations ("pi", "claude", "codex", …).
public struct ProviderInfo: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// One quota window (5-hour session, weekly, monthly, …).
public struct UsageWindow: Hashable, Sendable {
    public var label: String
    /// 0...100
    public var usedPercent: Double
    public var windowMinutes: Int?
    public var resetsAt: Date?

    public init(label: String, usedPercent: Double, windowMinutes: Int? = nil, resetsAt: Date? = nil) {
        self.label = label
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double { max(0, 100 - usedPercent) }

    /// Window names derived from its length are more reliable than CodexBar's labels
    /// (e.g. Codex free reports a 30-day window labelled "Session").
    static func label(minutes: Int?, fallback: String?) -> String {
        switch minutes {
        case 300: "5h"
        case 1440: "Daily"
        case 10080: "Weekly"
        case 43200, 44640, 40320: "Monthly"
        case let m? where m > 0 && m < 1440 && m % 60 == 0: "\(m / 60)h"
        case let m? where m > 0 && m % 1440 == 0: "\(m / 1440)d"
        default: fallback ?? "Usage"
        }
    }
}

/// Locally estimated spend (`codexbar cost`).
public struct CostSummary: Hashable, Sendable {
    public var todayUSD: Double?
    public var periodUSD: Double?
    public var periodLabel: String?

    public init(todayUSD: Double?, periodUSD: Double?, periodLabel: String? = nil) {
        self.todayUSD = todayUSD
        self.periodUSD = periodUSD
        self.periodLabel = periodLabel
    }
}

/// Everything the widget shows for one provider.
public struct ProviderUsage: Hashable, Sendable, Identifiable {
    public enum State: Hashable, Sendable {
        case loading
        case loaded
        case failed(String)
    }

    public var id: String
    public var name: String
    public var state: State
    public var plan: String?
    public var windows: [UsageWindow]
    public var cost: CostSummary?
    public var updatedAt: Date?

    public init(id: String, name: String, state: State = .loading, plan: String? = nil,
                windows: [UsageWindow] = [], cost: CostSummary? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.state = state
        self.plan = plan
        self.windows = windows
        self.cost = cost
        self.updatedAt = updatedAt
    }

    /// Body lines under the provider header; used by the panel to size itself.
    public var lineCount: Int {
        state == .loaded ? max(windows.count, 1) : 1
    }
}
