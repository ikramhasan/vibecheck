import AppKit
import CompanionCore
import Darwin
import OSLog

/// Brings forward the app a session runs in (terminal, T3 Code, an editor, …).
/// Agent-neutral: derived from the reported origin and the session's process tree.
/// Scripting Terminal or iTerm2 asks for Automation access on the first jump there.
@MainActor
enum SessionJumper {
    private nonisolated static let log = Logger(subsystem: "com.ikramulhasan.vibecheck", category: "jump")

    static func target(for session: AgentSession) -> JumpTarget? {
        JumpResolver.resolve(origin: session.origin, ancestry: localPID(of: session).map(ProcessTree.ancestry) ?? [])
    }

    /// Returns false when there's nowhere to go. Selects the exact tab (and tmux pane)
    /// in Terminal and iTerm2; other hosts are brought forward as a whole.
    @discardableResult
    static func jump(to session: AgentSession) -> Bool {
        let agent = localPID(of: session).flatMap(ProcessScanner.snapshot(pid:))
        if let agent, let tty = agent.tty, let tmux = agent.environment["TMUX"],
           let host = TmuxFocus.focus(paneTTY: tty, tmuxEnvironment: tmux),
           let terminal = JumpResolver.resolve(origin: nil, ancestry: ProcessTree.ancestry(of: host.clientPID)) {
            if TerminalFocus.focus(tty: host.clientTTY, bundleId: terminal.bundleId) { return true }
            return activate(terminal)
        }
        guard let target = target(for: session) else {
            log.info("No host app for \(session.id, privacy: .public)")
            return false
        }
        if let tty = agent?.tty, TerminalFocus.supports(target.bundleId),
           TerminalFocus.focus(tty: tty, bundleId: target.bundleId) {
            return true
        }
        return activate(target)
    }

    /// The agent itself, or for a remote session the ssh process that carries it.
    private static func localPID(of session: AgentSession) -> Int32? {
        session.pid ?? session.sshPID
    }

    private static func activate(_ target: JumpTarget) -> Bool {
        let running = target.appPID.flatMap(NSRunningApplication.init(processIdentifier:))
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleId).first
        guard let url = running?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleId) else { return false }
        // Opening through Launch Services is what a Dock click does: it reliably brings an
        // already-running app forward. `NSRunningApplication.activate()` can be ignored
        // since macOS 14 when the caller isn't the active app, which the panel never is.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { log.error("Open \(target.bundleId, privacy: .public) failed: \(error.localizedDescription, privacy: .public)") }
        }
        return true
    }
}

/// Process ancestry via libproc (no subprocesses, no permissions needed).
enum ProcessTree {
    static func ancestry(of pid: Int32) -> [ProcessNode] {
        var nodes: [ProcessNode] = []
        var current = pid
        // A depth cap guards against pid reuse forming a loop.
        while current > 1, nodes.count < 32, let info = bsdInfo(current) {
            let app = NSRunningApplication(processIdentifier: current)
            nodes.append(ProcessNode(pid: current, name: name(info),
                                     bundleId: app?.activationPolicy == .regular ? app?.bundleIdentifier : nil))
            current = Int32(info.pbi_ppid)
        }
        return nodes
    }

    private static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    private static func name(_ info: proc_bsdinfo) -> String {
        withUnsafeBytes(of: info.pbi_comm) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }
}
