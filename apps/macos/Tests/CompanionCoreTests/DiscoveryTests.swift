import Foundation
import Testing
@testable import CompanionCore

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct ClaudeDiscoveryTests {
    @Test func liveRegistryEntriesWithTranscripts() throws {
        let claude = try temporaryDirectory()
        let registry = claude.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
        let project = claude.appendingPathComponent("projects/-Users-me-My-App--worktrees")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data().write(to: project.appendingPathComponent("abc.jsonl"))
        try #"{"pid":10,"sessionId":"abc","cwd":"/Users/me/My App/.worktrees","name":"Fix bug","status":"busy","startedAt":1791734239811}"#
            .write(to: registry.appendingPathComponent("10.json"), atomically: true, encoding: .utf8)
        try #"{"pid":11,"sessionId":"new","cwd":"/tmp","status":"idle"}"#
            .write(to: registry.appendingPathComponent("11.json"), atomically: true, encoding: .utf8)
        try #"{"pid":12,"sessionId":"dead","cwd":"/tmp"}"#
            .write(to: registry.appendingPathComponent("12.json"), atomically: true, encoding: .utf8)

        let found = ClaudeDiscovery.discover(claudeDirectory: claude, isAlive: { $0 != 12 }) { pid in
            ProcessSnapshot(pid: pid, name: "claude", environment: ["TERM_PROGRAM": "iTerm.app"])
        }.sorted { $0.pid < $1.pid }

        #expect(found.map(\.sessionID) == ["abc", "new"])
        #expect(found[0].transcript?.lastPathComponent == "abc.jsonl")
        #expect(found[0].name == "Fix bug")
        #expect(found[0].statusWithoutTranscript == .working)
        #expect(found[0].origin == .init(termProgram: "iTerm.app"))
        #expect(found[1].transcript == nil)
        #expect(found[1].statusWithoutTranscript == .idle)
    }
}

@Suite struct CodexDiscoveryTests {
    @Test func openRolloutsBecomeSessions() {
        let root = URL(fileURLWithPath: "/home/.codex/sessions")
        let rollout = "/home/.codex/sessions/2026/10/11/rollout-2026-10-11T10-00-00-019c9446-4458-7ec0-980c-e2d97e99caf4.jsonl"
        let codex = ProcessSnapshot(pid: 20, name: "codex", cwd: "/repo")
        let other = ProcessSnapshot(pid: 21, name: "node")
        let found = CodexDiscovery.discover(sessionsDirectory: root, processes: [codex, other],
                                            openFiles: { $0 == 20 ? [rollout, "/dev/null", "/home/.codex/log/codex.log"] : [rollout] },
                                            sessionCWD: { _ in "/repo/shop" })
        #expect(found.count == 1)
        #expect(found.first?.sessionID == "019c9446-4458-7ec0-980c-e2d97e99caf4")
        #expect(found.first?.cwd == "/repo/shop")
        #expect(found.first?.pid == 20)
    }
}

@Suite struct PiDiscoveryTests {
    private func pi(_ pid: Int32, cwd: String, startedAt: TimeInterval, args: [String] = [], env: [String: String] = [:]) -> ProcessSnapshot {
        ProcessSnapshot(pid: pid, name: "node", arguments: ["node", "/opt/homebrew/bin/pi"] + args, environment: env,
                        cwd: cwd, startedAt: Date(timeIntervalSince1970: startedAt))
    }

    @Test func recognisesInteractivePi() {
        #expect(PiDiscovery.isInteractivePi(pi(1, cwd: "/", startedAt: 0)))
        #expect(PiDiscovery.isInteractivePi(pi(1, cwd: "/", startedAt: 0, args: ["--mode", "rpc"])))
        #expect(!PiDiscovery.isInteractivePi(pi(1, cwd: "/", startedAt: 0, args: ["-p", "hi"])))
        #expect(!PiDiscovery.isInteractivePi(pi(1, cwd: "/", startedAt: 0, args: ["--mode", "json"])))
        #expect(!PiDiscovery.isInteractivePi(pi(1, cwd: "/", startedAt: 0, env: ["PI_SUBAGENT_CHILD": "1"])))
        #expect(!PiDiscovery.isInteractivePi(ProcessSnapshot(pid: 2, name: "node", arguments: ["node", "server.js"])))
        #expect(PiDiscovery.isInteractivePi(ProcessSnapshot(pid: 3, name: "node", arguments: ["pi", "", "", ""])))
    }

    @Test func directoryNameMatchesPi() {
        #expect(PiDiscovery.directoryName("/Users/me/My Portfolio") == "--Users-me-My Portfolio--")
    }

    @Test func newestProcessTakesNewestFileWrittenSinceItStarted() {
        let dir = URL(fileURLWithPath: "/s")
        let old = PiDiscovery.SessionFile(url: dir.appendingPathComponent("2026_old.jsonl"), modifiedAt: Date(timeIntervalSince1970: 50))
        let a = PiDiscovery.SessionFile(url: dir.appendingPathComponent("2026_a.jsonl"), modifiedAt: Date(timeIntervalSince1970: 200))
        let b = PiDiscovery.SessionFile(url: dir.appendingPathComponent("2026_b.jsonl"), modifiedAt: Date(timeIntervalSince1970: 300))
        let first = pi(1, cwd: "/r", startedAt: 100)
        let second = pi(2, cwd: "/r", startedAt: 250)
        let assigned = PiDiscovery.assign(processes: [first, second], files: [old, a, b])
        #expect(assigned.map(\.0.pid) == [2, 1])
        #expect(assigned.map(\.1.lastPathComponent) == ["2026_b.jsonl", "2026_a.jsonl"])
    }

    @Test func processWithoutFileYetIsSkipped() {
        let stale = PiDiscovery.SessionFile(url: URL(fileURLWithPath: "/s/x_old.jsonl"), modifiedAt: Date(timeIntervalSince1970: 10))
        #expect(PiDiscovery.assign(processes: [pi(1, cwd: "/r", startedAt: 100)], files: [stale]).isEmpty)
    }

    @Test func explicitSessionArgumentWins() {
        let process = pi(1, cwd: "/r", startedAt: 100, args: ["--session", "/s/2026_pick.jsonl"])
        let assigned = PiDiscovery.assign(processes: [process], files: [])
        #expect(assigned.first?.1.path == "/s/2026_pick.jsonl")
        #expect(PiDiscovery.sessionID(fromFile: URL(fileURLWithPath: "/s/2026-10-10T17-15-44-149Z_01a126d0.jsonl")) == "01a126d0")
    }
}

@Suite struct ProcessScannerTests {
    @Test func readsOwnProcess() throws {
        let me = try #require(ProcessScanner.snapshot(pid: getpid()))
        #expect(me.cwd == FileManager.default.currentDirectoryPath)
        #expect(!me.arguments.isEmpty)
        #expect(me.environment["HOME"] == NSHomeDirectory())
    }
}

@MainActor
@Suite struct SessionStorePriorityTests {
    @Test func firstSourceWinsForTheSameSession() {
        let extensionReport = AgentSession(agent: .init(id: "pi", name: "pi"), sessionID: "1", cwd: "/",
                                           status: .needsAttention, updatedAt: .distantPast)
        let transcript = AgentSession(agent: .init(id: "pi", name: "pi"), sessionID: "1", cwd: "/",
                                      status: .working, updatedAt: .now)
        let store = SessionStore(sources: [StaticSessionSource([extensionReport]), StaticSessionSource([transcript])])
        store.start()
        #expect(store.sessions.map(\.status) == [.needsAttention])
    }
}

@Suite struct StatusPresentationTests {
    private func session(_ status: AgentSession.Status, kind: AgentSession.Attention.Kind? = nil,
                         activity: String? = nil, interrupted: Bool = false) -> AgentSession {
        AgentSession(agent: .init(id: "a", name: "A"), sessionID: "1", cwd: "/", status: status, task: "Task",
                     activity: activity, attention: kind.map { .init(kind: $0, message: "Q?") },
                     wasInterrupted: interrupted)
    }

    @Test func wordsPerState() {
        #expect(StatusPresentation(session(.needsAttention, kind: .permission)).word == "Waiting for approval")
        #expect(StatusPresentation(session(.needsAttention, kind: .question)).word == "Asking")
        #expect(StatusPresentation(session(.idle)).word == "Your turn")
        #expect(StatusPresentation(session(.idle, interrupted: true)).word == "Interrupted")
        #expect(StatusPresentation(session(.blocked)).word == "Blocked")
    }

    @Test func needsYouSortsFirst() {
        let ranks = [AgentSession.Status.needsAttention, .error, .blocked, .working, .idle].map { StatusPresentation(session($0)).urgency }
        #expect(ranks == ranks.sorted())
    }

    @Test func detailLines() {
        #expect(StatusPresentation.detail(session(.working, activity: "Editing auth.ts")) == "Working · Editing auth.ts")
        #expect(StatusPresentation.detail(session(.needsAttention, kind: .question)) == "Task")
        #expect(StatusPresentation.headline(session(.needsAttention, kind: .question)) == "Q?")
        #expect(StatusPresentation.detail(session(.idle)) == nil)
    }
}
