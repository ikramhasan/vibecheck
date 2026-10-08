import Foundation

/// Parses CodexBar CLI JSON (`usage`, `cost`, `config providers`). Lenient on purpose:
/// unknown fields are ignored and a malformed entry is skipped, not fatal, so a newer
/// CLI can't break the widget.
public enum CodexBarDecoder {
    // MARK: config providers

    public static func providers(_ data: Data) throws -> [ProviderInfo] {
        struct Raw: Decodable { let provider: String; let displayName: String? }
        return try JSONDecoder().decode([Lenient<Raw>].self, from: data)
            .compactMap(\.value)
            // Plugins whose bundle isn't loaded can't be fetched; hide them.
            .filter { $0.displayName != "plugin (not loaded)" }
            .map { ProviderInfo(id: $0.provider, name: $0.displayName ?? $0.provider) }
    }

    // MARK: usage

    public struct UsageEntry: Hashable, Sendable {
        public var provider: String
        public var error: String?
        public var plan: String?
        public var windows: [UsageWindow]
        public var updatedAt: Date?

        public init(provider: String, error: String? = nil, plan: String? = nil,
                    windows: [UsageWindow] = [], updatedAt: Date? = nil) {
            self.provider = provider
            self.error = error
            self.plan = plan
            self.windows = windows
            self.updatedAt = updatedAt
        }
    }

    public static func usage(_ data: Data) throws -> [UsageEntry] {
        try JSONDecoder().decode([Lenient<RawUsageEntry>].self, from: data)
            .compactMap(\.value)
            .map { raw in
                let labels = raw.rateWindowLabels ?? [:]
                let u = raw.usage
                var windows: [UsageWindow] = []
                for (key, w) in [("primary", u?.primary), ("secondary", u?.secondary), ("tertiary", u?.tertiary)] {
                    // Windows without a reset are placeholders (e.g. t3chat "Overage").
                    guard let w, let used = w.usedPercent, w.resetsAt != nil || w.windowMinutes != nil else { continue }
                    windows.append(UsageWindow(
                        label: UsageWindow.label(minutes: w.windowMinutes, fallback: labels[key]),
                        usedPercent: min(max(used, 0), 100),
                        windowMinutes: w.windowMinutes,
                        resetsAt: w.resetsAt.flatMap(parseDate)))
                }
                return UsageEntry(
                    provider: raw.provider,
                    error: raw.error?.message,
                    plan: (u?.loginMethod ?? u?.identity?.loginMethod).map(prettyPlan),
                    windows: windows,
                    updatedAt: u?.updatedAt.flatMap(parseDate))
            }
    }

    // MARK: cost

    public static func cost(_ data: Data) throws -> [String: CostSummary] {
        struct Raw: Decodable {
            let provider: String
            let sessionCostUSD: Double?
            let last30DaysCostUSD: Double?
            let historyLabel: String?
            let error: RawError?
        }
        var result: [String: CostSummary] = [:]
        for raw in try JSONDecoder().decode([Lenient<Raw>].self, from: data).compactMap(\.value)
        where raw.error == nil && (raw.sessionCostUSD != nil || raw.last30DaysCostUSD != nil) {
            result[raw.provider] = CostSummary(todayUSD: raw.sessionCostUSD,
                                               periodUSD: raw.last30DaysCostUSD,
                                               periodLabel: raw.historyLabel)
        }
        return result
    }

    // MARK: helpers

    /// "free" → "Free", "Free_signed_out" → "Free signed out", "Claude Pro" unchanged.
    static func prettyPlan(_ s: String) -> String {
        let spaced = s.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    private struct RawError: Decodable { let message: String? }
    private struct RawWindow: Decodable {
        let usedPercent: Double?
        let windowMinutes: Int?
        let resetsAt: String?
    }
    private struct RawIdentity: Decodable { let loginMethod: String? }
    private struct RawUsage: Decodable {
        let primary: RawWindow?
        let secondary: RawWindow?
        let tertiary: RawWindow?
        let loginMethod: String?
        let identity: RawIdentity?
        let updatedAt: String?
    }
    private struct RawUsageEntry: Decodable {
        let provider: String
        let usage: RawUsage?
        let error: RawError?
        let rateWindowLabels: [String: String]?
    }
}

/// Decodes to nil instead of throwing, so one bad array element doesn't sink the rest.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
