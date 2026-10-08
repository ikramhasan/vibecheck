import AppKit
import CompanionCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: SessionStore?
    private var usage: UsageStore?
    private var controller: EdgePanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let source: SessionSource = args.contains("--demo")
            ? StaticSessionSource(DemoData.sessions)
            : StatusDirectorySource()

        // Register further non-reporter sources here, e.g. a log-tailing source
        // for an agent that can't run an integration hook.
        let store = SessionStore(sources: [source])
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
    static let sessions: [AgentSession] = [
        AgentSession(agent: .init(id: "pi", name: "pi"), sessionID: "demo-1", cwd: NSHomeDirectory() + "/shop/web",
                     status: .working, task: "Add a pricing page to the site",
                     activity: "Reading src/pages/index.tsx", startedAt: .now),
        AgentSession(agent: .init(id: "codex", name: "Codex"), sessionID: "demo-2", cwd: NSHomeDirectory() + "/shop/api",
                     status: .needsAttention, task: "Add Stripe checkout to the pricing page",
                     attention: .init(kind: .question, message: "Use Stripe Checkout or Payment Element?"),
                     startedAt: .now.addingTimeInterval(1)),
    ]
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
