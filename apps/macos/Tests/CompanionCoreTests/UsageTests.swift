import Foundation
import Testing
@testable import CompanionCore

/// Fixtures trimmed from real `codexbar` 0.73.0 output.
@Suite struct CodexBarDecoderTests {
    @Test func decodesClaudeSessionAndWeekly() throws {
        let json = """
        [{"provider":"claude","source":"web","rateWindowLabels":{"primary":"Session","secondary":"Weekly"},
          "usage":{"loginMethod":"Claude Pro","updatedAt":"2026-10-07T22:13:10Z",
            "primary":{"resetsAt":"2026-10-08T01:49:59Z","usedPercent":6,"windowMinutes":300},
            "secondary":{"resetsAt":"2026-10-13T22:59:59Z","usedPercent":29,"windowMinutes":10080},
            "tertiary":null,"newFieldFromTheFuture":{"x":1}}}]
        """
        let e = try #require(try CodexBarDecoder.usage(Data(json.utf8)).first)
        #expect(e.provider == "claude")
        #expect(e.error == nil)
        #expect(e.plan == "Claude Pro")
        #expect(e.windows.map(\.label) == ["5h", "Weekly"])
        #expect(e.windows.map(\.usedPercent) == [6, 29])
        #expect(e.windows[0].resetsAt == CodexBarDecoder.parseDate("2026-10-08T01:49:59Z"))
    }

    @Test func labelsWindowByLengthNotCodexBarLabel() throws {
        // Codex free plan: a 30-day window that CodexBar labels "Session".
        let json = """
        [{"provider":"codex","rateWindowLabels":{"primary":"Session"},
          "usage":{"loginMethod":"free","primary":{"usedPercent":0,"windowMinutes":43200,"resetsAt":"2026-11-06T22:13:06Z"},
                   "secondary":null}}]
        """
        let e = try #require(try CodexBarDecoder.usage(Data(json.utf8)).first)
        #expect(e.windows.map(\.label) == ["Monthly"])
        #expect(e.plan == "Free")
    }

    @Test func dropsPlaceholderWindowsAndKeepsErrors() throws {
        let json = """
        [{"provider":"t3chat","rateWindowLabels":{"primary":"Base","secondary":"Overage"},
          "usage":{"loginMethod":"Free_signed_out","primary":{"usedPercent":0,"windowMinutes":240,"resetsAt":"2026-10-09T18:24:10Z"},
                   "secondary":{"usedPercent":0,"resetDescription":"Overage"}}},
         {"provider":"gemini","source":"auto","error":{"message":"Not logged in to Gemini.","kind":"provider","code":1}},
         "garbage",
         {"provider":"kiro","usage":{"primary":{"usedPercent":57.95,"resetsAt":"2026-11-01T00:00:00Z"}}}]
        """
        let entries = try CodexBarDecoder.usage(Data(json.utf8))
        #expect(entries.map(\.provider) == ["t3chat", "gemini", "kiro"])
        #expect(entries[0].windows.map(\.label) == ["4h"])
        #expect(entries[0].plan == "Free signed out")
        #expect(entries[1].error == "Not logged in to Gemini.")
        #expect(entries[2].windows.first?.label == "Usage")
    }

    @Test func decodesCost() throws {
        let json = """
        [{"provider":"claude","sessionCostUSD":33.31,"last30DaysCostUSD":456.09,"historyLabel":"Last 30 days"},
         {"provider":"cursor","error":{"code":1,"message":"Cursor API error: HTTP 307"}},
         {"provider":"pi"}]
        """
        let c = try CodexBarDecoder.cost(Data(json.utf8))
        #expect(c.keys.sorted() == ["claude"])
        #expect(c["claude"] == CostSummary(todayUSD: 33.31, periodUSD: 456.09, periodLabel: "Last 30 days"))
    }

    @Test func decodesProvidersAndSkipsUnloadedPlugins() throws {
        let json = """
        [{"provider":"codex","displayName":"Codex","enabled":false,"defaultEnabled":true},
         {"provider":"kimik2","displayName":"plugin (not loaded)","enabled":false}]
        """
        #expect(try CodexBarDecoder.providers(Data(json.utf8)) == [.init(id: "codex", name: "Codex")])
    }
}

@Suite struct AgentPreferencesTests {
    @Test func addingEnablesUsageAndRemovingClearsEverything() {
        var p = AgentPreferences()
        #expect(p.showsStatus("pi"))       // status is opt-out
        #expect(!p.showsUsage("pi"))       // usage is opt-in
        p.add("claude")
        #expect(p.added == ["claude"])
        #expect(p.showsUsage("claude"))
        p.setStatus(false, for: "claude")
        #expect(!p.showsStatus("claude"))
        p.remove("claude")
        #expect(p == AgentPreferences())
    }

    @Test func hidingAnUnaddedAgentAddsItSoItStaysVisibleInSettings() {
        var p = AgentPreferences()
        p.setStatus(false, for: "pi")
        #expect(p.added == ["pi"])
        #expect(!p.showsUsage("pi"))
    }

    @MainActor @Test func persists() throws {
        let suite = "AgentPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = AppSettings(defaults: defaults)
        a.agents.add("codex")
        a.agents.setStatus(false, for: "pi")
        let b = AppSettings(defaults: defaults)
        #expect(b.agents == a.agents)
    }
}

@Suite struct WindowLabelTests {
    @Test func labels() {
        #expect(UsageWindow.label(minutes: 300, fallback: "Session") == "5h")
        #expect(UsageWindow.label(minutes: 10080, fallback: nil) == "Weekly")
        #expect(UsageWindow.label(minutes: nil, fallback: "Session") == "Session")
        #expect(UsageWindow.label(minutes: 4320, fallback: nil) == "3d")
    }
}

private struct FakeFetcher: UsageFetching {
    var failing: Set<String> = []
    func providers() async throws -> [ProviderInfo] {
        [.init(id: "codex", name: "Codex"), .init(id: "claude", name: "Claude")]
    }
    func usage(provider: String) async throws -> CodexBarDecoder.UsageEntry? {
        if failing.contains(provider) { return .init(provider: provider, error: "Not logged in") }
        return .init(provider: provider, windows: [.init(label: "5h", usedPercent: 10, windowMinutes: 300)])
    }
    func cost(provider: String) async throws -> CostSummary? { .init(todayUSD: 1, periodUSD: 2) }
    func supportsCost(_ provider: String) -> Bool { provider == "claude" }
}

@MainActor
@Suite struct UsageStoreTests {
    private func settle(_ store: UsageStore, until done: () -> Bool) async {
        for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func fetchesEnabledProvidersSortedByName() async {
        let store = UsageStore(fetcher: FakeFetcher(failing: ["codex"]))
        await store.loadCatalog()
        store.setEnabled(["codex", "claude"])
        #expect(store.usage.map(\.name) == ["Claude", "Codex"])
        await settle(store) { store.usage.allSatisfy { $0.state != .loading } }

        let claude = store.usage[0], codex = store.usage[1]
        #expect(claude.state == .loaded)
        #expect(claude.windows.count == 1)
        #expect(claude.cost?.todayUSD == 1)
        #expect(codex.state == .failed("Not logged in"))
        #expect(codex.cost == nil)

        store.setEnabled(["claude"])
        #expect(store.usage.map(\.id) == ["claude"])
    }

    @Test func missingCLIIsReported() {
        let store = UsageStore(fetcher: nil)
        #expect(store.catalogState == .unavailable("CodexBar CLI not found"))
    }
}
