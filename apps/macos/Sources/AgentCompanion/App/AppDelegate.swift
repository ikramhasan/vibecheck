import AppKit
import CompanionCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: SessionStore?
    private var controller: EdgePanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let source: SessionSource = args.contains("--demo")
            ? StaticSessionSource(DemoData.sessions)
            : StatusDirectorySource()

        // Register further non-reporter sources here, e.g. a log-tailing source
        // for an agent that can't run an integration hook.
        let store = SessionStore(sources: [source])
        let controller = EdgePanelController(store: store)
        self.store = store
        self.controller = controller
        controller.show()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
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
