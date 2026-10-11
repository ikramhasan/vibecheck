import AppKit
import CompanionCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: SessionStore?
    private var usage: UsageStore?
    private var controller: EdgePanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let sources: [SessionSource] = args.contains("--demo")
            ? [StaticSessionSource(DemoData.sessions)]
            : [StatusDirectorySource(), TranscriptSessionSource()]
        let store = SessionStore(sources: sources)
        let usage = UsageStore(fetcher: args.contains("--demo") ? DemoUsage() : CodexBarCLI.locate())
        let settings = AppSettings()
        let controller = EdgePanelController(store: store, usage: usage, settings: settings)
        self.store = store
        self.usage = usage
        self.controller = controller

        observeAgentPreferences(settings) { prefs in
            store.setHiddenAgents(prefs.hiddenStatus)
            usage.setEnabled(prefs.usage)
        }
        controller.show()
        store.start()
        usage.start()
        if args.contains("--settings") { controller.showPage(.settings) }
    }

    /// Calls `apply` now and after every change to `settings.agents`.
    private func observeAgentPreferences(_ settings: AppSettings,
                                         _ apply: @escaping @MainActor (AgentPreferences) -> Void) {
        let prefs = withObservationTracking { settings.agents } onChange: { [weak self] in
            Task { @MainActor in self?.observeAgentPreferences(settings, apply) }
        }
        apply(prefs)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
        usage?.stop()
    }
}

enum DemoData {
    /// Sample projects under ~/Projects when they exist (so icons resolve), else made-up paths.
    private static func project(_ name: String, fallback: String) -> String {
        let real = NSHomeDirectory() + "/Home/Projects/" + name
        return FileManager.default.fileExists(atPath: real) ? real : NSHomeDirectory() + "/" + fallback
    }

    static let sessions: [AgentSession] = {
        let companion = project("AgentCompanion", fallback: "work/AgentCompanion")
        let web = project("Gitrens", fallback: "work/shop-web")
        let cli = NSHomeDirectory() + "/work/cli"
        let now = Date.now
        return [
            AgentSession(agent: .init(id: "pi", name: "pi"), sessionID: "demo-1", cwd: companion + "/apps/macos",
                         model: "claude-opus", status: .working, task: "Redesign collapsed tab and session list",
                         activity: "Editing EdgePanelView.swift", startedAt: now.addingTimeInterval(-600),
                         updatedAt: now.addingTimeInterval(-240)),
            AgentSession(agent: .init(id: "claude", name: "Claude"), sessionID: "demo-2", cwd: web,
                         status: .needsAttention, task: "Migrate auth middleware to edge runtime",
                         attention: .init(kind: .permission, message: "Allow edit to config.prod.yml?"),
                         startedAt: now.addingTimeInterval(-900), updatedAt: now.addingTimeInterval(-60)),
            AgentSession(agent: .init(id: "codex", name: "Codex"), sessionID: "demo-3", cwd: web,
                         status: .working, task: "Add Stripe checkout to pricing page", activity: "Running npm test",
                         context: .init(usedTokens: 196_000, windowTokens: 258_400),
                         startedAt: now.addingTimeInterval(-1200), updatedAt: now.addingTimeInterval(-540)),
            AgentSession(agent: .init(id: "cursor", name: "Cursor"), sessionID: "demo-4", cwd: cli,
                         status: .idle, task: "Fix flaky snapshot test", activity: "Done · 3 files changed",
                         startedAt: now.addingTimeInterval(-2400), updatedAt: now.addingTimeInterval(-720)),
        ]
    }()
}

/// Canned usage for `--demo`: no CLI, no network.
struct DemoUsage: UsageFetching {
    func providers() async throws -> [ProviderInfo] {
        [.init(id: "claude", name: "Claude"), .init(id: "codex", name: "Codex"),
         .init(id: "pi", name: "Pi"), .init(id: "cursor", name: "Cursor"), .init(id: "gemini", name: "Gemini")]
    }

    func usage(provider: String) async throws -> CodexBarDecoder.UsageEntry? {
        try await Task.sleep(for: .milliseconds(400))
        let now = Date()
        switch provider {
        case "claude":
            return .init(provider: provider, error: nil, plan: "Claude Max", windows: [
                .init(label: "5h", usedPercent: 37, windowMinutes: 300, resetsAt: now.addingTimeInterval(3.6 * 3600)),
                .init(label: "Weekly", usedPercent: 82, windowMinutes: 10080, resetsAt: now.addingTimeInterval(6 * 86400)),
            ], updatedAt: now)
        case "codex":
            return .init(provider: provider, error: nil, plan: "Plus", windows: [
                .init(label: "5h", usedPercent: 12, windowMinutes: 300, resetsAt: now.addingTimeInterval(2.2 * 3600)),
                .init(label: "Weekly", usedPercent: 41, windowMinutes: 10080, resetsAt: now.addingTimeInterval(3 * 86400)),
            ], updatedAt: now)
        default:
            return .init(provider: provider, error: "Not logged in", plan: nil, windows: [], updatedAt: nil)
        }
    }

    func cost(provider: String) async throws -> CostSummary? {
        switch provider {
        case "claude": .init(todayUSD: 33.31, periodUSD: 456.09)
        case "codex": .init(todayUSD: 4.12, periodUSD: 61.80)
        default: nil
        }
    }

    func supportsCost(_ provider: String) -> Bool { true }
}
