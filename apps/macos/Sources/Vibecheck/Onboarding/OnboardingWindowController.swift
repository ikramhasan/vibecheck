import AppKit
import CompanionCore
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let window: NSWindow

    init(settings: AppSettings, machines: RemoteMachines, launchAtLogin: LaunchAtLogin?) {
        self.settings = settings
        window = NSWindow(contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        let root = OnboardingView(settings: settings, launchAtLogin: launchAtLogin,
                                  onFinish: { [weak self] in self?.window.close() })
            .environment(settings)
            .environment(machines)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to vibecheck"
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    func show() {
        if settings.agents.added.isEmpty {
            for agent in OnboardingAgent.all where agent.isInstalled { settings.agents.observe(agent, true) }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        settings.hasCompletedOnboarding = true
    }
}

struct OnboardingAgent: Identifiable {
    let id: String
    let name: String
    let detail: String
    let reportsSessions: Bool
    let reportsUsage: Bool
    let dataPath: String

    static let all = [
        OnboardingAgent(id: "claude", name: "Claude Code", detail: "Sessions and plan usage", reportsSessions: true,
                        reportsUsage: true, dataPath: ".claude"),
        OnboardingAgent(id: "codex", name: "Codex", detail: "Sessions and plan usage", reportsSessions: true,
                        reportsUsage: true, dataPath: ".codex"),
        OnboardingAgent(id: "pi", name: "pi", detail: "Sessions", reportsSessions: true, reportsUsage: false,
                        dataPath: ".pi"),
        OnboardingAgent(id: "kiro", name: "Kiro", detail: "Plan usage", reportsSessions: false, reportsUsage: true,
                        dataPath: "Library/Application Support/kiro-cli"),
    ]

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/" + dataPath)
    }
}

extension AgentPreferences {
    func observes(_ agent: OnboardingAgent) -> Bool {
        added.contains(agent.id) && showsStatus(agent.id)
    }

    mutating func observe(_ agent: OnboardingAgent, _ on: Bool) {
        if on {
            setStatus(true, for: agent.id)
            setUsage(true, for: agent.id)
        } else {
            remove(agent.id)
            if agent.reportsSessions { setStatus(false, for: agent.id) }
        }
    }
}
