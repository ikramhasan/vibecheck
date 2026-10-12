import Foundation
import SQLite3
import Testing
@testable import CompanionCore

@Suite struct ClaudeUsageTests {
    static let teamResponse = """
    {"five_hour":{"utilization":18.0,"resets_at":"2026-10-12T14:59:59.797972+00:00"},
     "seven_day":null,"seven_day_opus":null,"seven_day_sonnet":null,
     "extra_usage":{"is_enabled":false},
     "limits":[
       {"kind":"session","group":"session","percent":18,"resets_at":"2026-10-12T14:59:59.797972+00:00","scope":null},
       {"kind":"weekly_scoped","group":"weekly","percent":0,"resets_at":"2026-10-15T09:00:00+00:00",
        "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}]}
    """

    @Test func mapsSessionAndModelScopedWeekly() throws {
        let report = try ClaudeUsage.report(Data(Self.teamResponse.utf8), plan: "Team")
        #expect(report.plan == "Team")
        #expect(report.windows.map(\.label) == ["5h", "Fable Weekly"])
        #expect(report.windows.map(\.usedPercent) == [18, 0])
        #expect(report.windows[1].resetsAt == ClaudeUsage.parseDate("2026-10-15T09:00:00Z"))
    }

    @Test func mapsWeeklyAndSonnet() throws {
        let json = """
        {"five_hour":{"utilization":6,"resets_at":"2026-10-08T01:49:59Z"},
         "seven_day":{"utilization":29,"resets_at":"2026-10-13T22:59:59Z"},
         "seven_day_sonnet":{"utilization":3,"resets_at":"2026-10-13T22:59:59Z"},
         "limits":[{"kind":"weekly_scoped","group":"weekly","percent":40,"scope":{"model":{"display_name":"All models"}}}]}
        """
        let report = try ClaudeUsage.report(Data(json.utf8), plan: nil)
        #expect(report.windows.map(\.label) == ["5h", "Weekly", "Sonnet Weekly"])
    }

    @Test func noWindowsIsAnErrorNotAZeroPercentPlaceholder() {
        let json = #"{"five_hour":null,"seven_day":null,"limits":[]}"#
        #expect(throws: UsageError("No plan limits reported")) {
            try ClaudeUsage.report(Data(json.utf8), plan: nil)
        }
    }

    @Test func plans() {
        #expect(ClaudeUsage.planName(subscription: "team", tier: "default_claude_max_5x") == "Team")
        #expect(ClaudeUsage.planName(subscription: "max", tier: "default_claude_max_20x") == "Max 20x")
        #expect(ClaudeUsage.planName(subscription: "pro", tier: nil) == "Pro")
        #expect(ClaudeUsage.planName(subscription: nil, tier: nil) == nil)
    }

    private func provider(file: String?, keychain: String?, now: Date = Date(timeIntervalSince1970: 1_000)) throws -> ClaudeUsage {
        let url = FileManager.default.temporaryDirectory.appending(path: "claude-\(UUID().uuidString).json")
        if let file { try Data(file.utf8).write(to: url) }
        return ClaudeUsage(credentialsFile: url, keychain: { keychain.map { Data($0.utf8) } }, now: { now })
    }

    private static func credentials(token: String = "tok", expiresAt: Int) -> String {
        #"{"claudeAiOauth":{"accessToken":"\#(token)","expiresAt":\#(expiresAt),"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}"#
    }

    @Test func readsClaudeCodesKeychainItemWhenThereIsNoFile() async throws {
        let claude = try provider(file: nil, keychain: Self.credentials(expiresAt: 2_000_000))
        #expect(try await claude.credentials() == .init(accessToken: "tok", plan: "Max 20x"))
    }

    @Test func prefersAValidCredentialsFile() async throws {
        let claude = try provider(file: Self.credentials(token: "file", expiresAt: 2_000_000),
                                  keychain: Self.credentials(token: "keychain", expiresAt: 2_000_000))
        #expect(try await claude.credentials().accessToken == "file")
    }

    @Test func expiredFileFallsBackToTheKeychain() async throws {
        let claude = try provider(file: Self.credentials(token: "file", expiresAt: 999_000),
                                  keychain: Self.credentials(token: "keychain", expiresAt: 2_000_000))
        #expect(try await claude.credentials().accessToken == "keychain")
    }

    @Test func expiredEverywhereIsReportedAsExpired() async throws {
        let claude = try provider(file: Self.credentials(expiresAt: 999_000), keychain: "not json")
        await #expect(throws: UsageError("Sign-in expired. Run claude to refresh it")) { try await claude.credentials() }
    }

    @Test func expiredTokenIsNotSentOrRefreshed() async throws {
        let claude = try provider(file: nil, keychain: Self.credentials(expiresAt: 999_000))
        await #expect(throws: UsageError("Sign-in expired. Run claude to refresh it")) { try await claude.credentials() }
    }

    @Test func missingCredentials() async throws {
        let claude = try provider(file: nil, keychain: nil)
        await #expect(throws: UsageError("Not signed in. Run claude to sign in")) { try await claude.credentials() }
    }
}

@Suite struct CodexUsageTests {
    @Test func mapsWindowsShortestFirstAndExtraModelLimits() throws {
        let json = """
        {"plan_type":"plus","rate_limit":{
           "primary_window":{"used_percent":19,"limit_window_seconds":604800,"reset_at":1776395384},
           "secondary_window":{"used_percent":4,"limit_window_seconds":18000,"reset_at":1776216359}},
         "additional_rate_limits":[{"limit_name":"Spark","metered_feature":"gpt_5_3_codex_spark","rate_limit":{
           "primary_window":{"used_percent":2,"limit_window_seconds":18000,"reset_at":1776216359},"secondary_window":null}}]}
        """
        let report = try CodexUsage.report(Data(json.utf8))
        #expect(report.plan == "Plus")
        #expect(report.windows.map(\.label) == ["5h", "Weekly", "Spark 5h"])
        #expect(report.windows.map(\.usedPercent) == [4, 19, 2])
        #expect(report.windows[0].resetsAt == Date(timeIntervalSince1970: 1776216359))
    }

    @Test func labelsAThirtyDayWindowMonthly() throws {
        let json = #"{"plan_type":"free","rate_limit":{"primary_window":{"used_percent":7,"limit_window_seconds":2592000,"reset_at":1}}}"#
        #expect(try CodexUsage.report(Data(json.utf8)).windows.map(\.label) == ["Monthly"])
    }

    @Test func noWindowsIsAnError() {
        #expect(throws: UsageError("No plan limits reported")) {
            try CodexUsage.report(Data(#"{"rate_limit":{"primary_window":null}}"#.utf8))
        }
    }

    @Test func plans() {
        #expect(CodexUsage.planName("pro") == "Pro 20x")
        #expect(CodexUsage.planName("prolite") == "Pro 5x")
        #expect(CodexUsage.planName("free_workspace") == "Free Workspace")
    }

    private func codex(_ auth: String, now: Date = Date(timeIntervalSince1970: 1_000)) throws -> CodexUsage {
        let url = FileManager.default.temporaryDirectory.appending(path: "codex-\(UUID().uuidString).json")
        try Data(auth.utf8).write(to: url)
        return CodexUsage(authFile: url, now: { now })
    }

    private static func jwt(exp: Int) -> String {
        let payload = Data(#"{"exp":\#(exp)}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        return "e30.\(payload).sig"
    }

    @Test func readsTokenAndAccount() throws {
        let codex = try codex(#"{"tokens":{"access_token":"\#(Self.jwt(exp: 2_000))","account_id":"acct"}}"#)
        #expect(try codex.credentials() == .init(accessToken: Self.jwt(exp: 2_000), accountID: "acct"))
    }

    @Test func expiredTokenIsNotSentOrRefreshed() throws {
        let codex = try codex(#"{"tokens":{"access_token":"\#(Self.jwt(exp: 500))","refresh_token":"r"}}"#)
        #expect(throws: UsageError("Sign-in expired. Run codex to refresh it")) { try codex.credentials() }
    }

    @Test func apiKeyHasNoPlanLimits() throws {
        let codex = try codex(#"{"OPENAI_API_KEY":"sk-x","tokens":null}"#)
        #expect(throws: UsageError("Signed in with an API key, which has no plan limits")) { try codex.credentials() }
    }
}

@Suite struct KiroUsageTests {
    static let response = """
    {"nextDateReset":1793491200.0,"overageConfiguration":{"overageStatus":"ENABLED"},
     "subscriptionInfo":{"subscriptionTitle":"KIRO POWER"},
     "usageBreakdownList":[{"resourceType":"CREDIT","currentUsageWithPrecision":13603.49,
       "currentOveragesWithPrecision":3603.49,"usageLimitWithPrecision":10000.0,"overageCapWithPrecision":10000.0,
       "nextDateReset":1793491200.0,"bonuses":[]}]}
    """

    @Test func mapsCreditsAndOverage() throws {
        let report = try KiroUsage.report(Data(Self.response.utf8))
        #expect(report.plan == "Kiro Power")
        #expect(report.windows.map(\.label) == ["Monthly", "Overage"])
        #expect(report.windows.map { $0.usedPercent.rounded() } == [100, 36])
        #expect(report.windows[0].resetsAt == Date(timeIntervalSince1970: 1793491200))
    }

    @Test func endpoints() {
        #expect(KiroUsage.endpoint(arn: "arn:aws:codewhisperer:us-east-1:123:profile/ABC")?.host == "codewhisperer.us-east-1.amazonaws.com")
        #expect(KiroUsage.endpoint(arn: "arn:aws:codewhisperer:eu-central-1:123:profile/ABC")?.host == "q.eu-central-1.amazonaws.com")
        #expect(KiroUsage.endpoint(arn: "arn:aws:codewhisperer:ap-south-1:123:profile/ABC") == nil)
    }

    private func database(token: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "kiro \(UUID().uuidString).sqlite3")
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let profile = #"{"arn":"arn:aws:codewhisperer:us-east-1:123:profile/ABC"}"#
        let sql = """
        CREATE TABLE auth_kv(key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE state(key TEXT PRIMARY KEY, value TEXT);
        INSERT INTO auth_kv VALUES('kirocli:odic:token', '\(token)');
        INSERT INTO state VALUES('api.codewhisperer.profile', '\(profile)');
        """
        try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        return url
    }

    @Test func readsTokenAndProfileWithoutTouchingTheDatabase() throws {
        let url = try database(token: #"{"access_token":"tok","expires_at":"2026-10-12T12:35:26.289526Z"}"#)
        let before = try Data(contentsOf: url)
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        let kiro = KiroUsage(database: url, now: { ClaudeUsage.parseDate("2026-10-12T12:00:00Z")! })
        let credentials = try kiro.credentials()
        #expect(credentials.accessToken == "tok")
        #expect(credentials.endpoint.host == "codewhisperer.us-east-1.amazonaws.com")
        #expect(try Data(contentsOf: url) == before)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == modified)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(!siblings.contains { $0.hasPrefix(url.lastPathComponent + "-") })
    }

    @Test func expiredTokenIsNotSent() throws {
        let url = try database(token: #"{"access_token":"tok","expires_at":"2026-10-12T12:35:26Z"}"#)
        let kiro = KiroUsage(database: url, now: { ClaudeUsage.parseDate("2026-10-12T13:00:00Z")! })
        #expect(throws: UsageError("Sign-in expired. Run kiro-cli to refresh it")) { try kiro.credentials() }
    }

    @Test func missingDatabase() {
        let kiro = KiroUsage(database: URL(fileURLWithPath: "/nonexistent/data.sqlite3"), now: Date.init)
        #expect(throws: UsageError("Not signed in. Run kiro-cli login")) { try kiro.credentials() }
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
        #expect(UsageWindow.label(minutes: 300) == "5h")
        #expect(UsageWindow.label(minutes: 10080) == "Weekly")
        #expect(UsageWindow.label(minutes: nil) == "Usage")
        #expect(UsageWindow.label(minutes: 4320) == "3d")
    }
}

private struct FakeProvider: UsageProvider {
    let info: ProviderInfo
    var error: Error?
    func fetch() async throws -> UsageReport {
        if let error { throw error }
        return UsageReport(windows: [.init(label: "5h", usedPercent: 10, windowMinutes: 300)])
    }
}

@MainActor
@Suite struct UsageStoreTests {
    private func settle(_ store: UsageStore, until done: () -> Bool) async {
        for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func fetchesEnabledProvidersSortedByName() async {
        let store = UsageStore(providers: [
            FakeProvider(info: .init(id: "codex", name: "Codex"), error: UsageError("Not signed in")),
            FakeProvider(info: .init(id: "claude", name: "Claude")),
        ])
        #expect(store.catalog.map(\.name) == ["Claude", "Codex"])
        store.setEnabled(["codex", "claude", "pi"])
        #expect(store.usage.map(\.name) == ["Claude", "Codex"])
        await settle(store) { store.usage.allSatisfy { $0.state != .loading } }

        #expect(store.usage[0].state == .loaded)
        #expect(store.usage[0].windows.count == 1)
        #expect(store.usage[1].state == .failed("Not signed in"))

        store.setEnabled(["claude"])
        #expect(store.usage.map(\.id) == ["claude"])
    }
}
