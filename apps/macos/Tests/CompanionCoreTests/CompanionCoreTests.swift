import Foundation
import Testing
@testable import CompanionCore

private func session(_ id: String, _ status: AgentSession.Status, message: String? = nil) -> AgentSession {
    AgentSession(agent: .init(id: "test", name: "Test"), sessionID: id, cwd: "/tmp", status: status,
                 attention: message.map { .init(kind: .question, message: $0) })
}

@Suite struct PanelPresentationTests {
    @Test func hiddenWhenNothingRuns() {
        var p = PanelPresentation()
        p.update(sessions: [])
        #expect(p.mode == .hidden)
    }

    @Test func collapsedWhileSessionsRun() {
        var p = PanelPresentation()
        p.update(sessions: [session("a", .working)])
        #expect(p.mode == .collapsed)
        p.update(sessions: [])
        #expect(p.mode == .hidden)
    }

    @Test func hoverExpandsAndLeavingCollapses() {
        var p = PanelPresentation()
        p.update(sessions: [session("a", .working)])
        p.setHovering(true)
        #expect(p.mode == .expanded)
        p.setHovering(false)
        #expect(p.mode == .collapsed)
    }

    @Test func attentionExpandsUntilSeen() {
        var p = PanelPresentation()
        p.update(sessions: [session("a", .working)])
        p.update(sessions: [session("a", .needsAttention, message: "Proceed?")])
        #expect(p.mode == .expanded)

        // Stays open through unrelated updates until the user has looked at it.
        p.update(sessions: [session("a", .needsAttention, message: "Proceed?"), session("b", .working)])
        #expect(p.mode == .expanded)

        p.setHovering(true)
        p.setHovering(false)
        #expect(p.mode == .collapsed)

        // Same request still pending, already seen: stays collapsed.
        p.update(sessions: [session("a", .needsAttention, message: "Proceed?")])
        #expect(p.mode == .collapsed)
    }

    @Test func newRequestReopens() {
        var p = PanelPresentation()
        p.update(sessions: [session("a", .needsAttention, message: "Q1")])
        p.setHovering(true); p.setHovering(false)
        #expect(p.mode == .collapsed)
        p.update(sessions: [session("a", .needsAttention, message: "Q2")])
        #expect(p.mode == .expanded)
    }

    @Test func resolvedThenSameQuestionAgainReopens() {
        var p = PanelPresentation()
        p.update(sessions: [session("a", .needsAttention, message: "Q")])
        p.setHovering(true); p.setHovering(false)
        p.update(sessions: [session("a", .working)])
        p.update(sessions: [session("a", .needsAttention, message: "Q")])
        #expect(p.mode == .expanded)
    }

    @Test func resolvedWithoutLookingCollapses() {
        var p = PanelPresentation()
        p.update(sessions: [session("a", .needsAttention, message: "Q")])
        #expect(p.mode == .expanded)
        p.update(sessions: [session("a", .working)])
        #expect(p.mode == .collapsed)
    }
}

@Suite struct StatusFileTests {
    static let sample = """
    {"schemaVersion":1,"agent":{"id":"pi","name":"pi"},
     "session":{"id":"s1","cwd":"/work","name":"","model":"m"},
     "pid":123,"status":"needs_attention","task":"Do it","activity":"",
     "attention":{"kind":"permission","message":"Run rm?"},
     "startedAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:05Z"}
    """

    @Test func decodesContract() throws {
        let s = try StatusFileDecoder.decode(Data(Self.sample.utf8))
        #expect(s.id == "pi/s1")
        #expect(s.status == .needsAttention)
        #expect(s.attention == .init(kind: .permission, message: "Run rm?"))
        #expect(s.name == nil)      // empty strings normalised away
        #expect(s.activity == nil)
        #expect(s.pid == 123)
    }

    @Test func rejectsUnknownSchema() {
        let data = Data(Self.sample.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2").utf8)
        #expect(throws: StatusFileDecoder.DecodeError.unsupportedSchema(2)) {
            try StatusFileDecoder.decode(data)
        }
    }

    @Test func scanPrunesDeadAndStaleAndSkipsGarbage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func write(_ name: String, pid: Int?, updated: String) throws {
            let pidField = pid.map { "\"pid\":\($0)," } ?? ""
            let json = """
            {"schemaVersion":1,"agent":{"id":"x","name":"X"},"session":{"id":"\(name)","cwd":"/"},
             \(pidField)"status":"working","updatedAt":"\(updated)"}
            """
            try json.write(to: dir.appendingPathComponent("\(name).json"), atomically: true, encoding: .utf8)
        }
        try write("alive", pid: 1, updated: "2026-01-01T00:00:00Z")
        try write("dead", pid: 2, updated: "2026-01-01T00:00:00Z")
        try write("fresh", pid: nil, updated: "2026-01-01T00:10:00Z")
        try write("stale", pid: nil, updated: "2025-01-01T00:00:00Z")
        try "not json".write(to: dir.appendingPathComponent("junk.json"), atomically: true, encoding: .utf8)

        let now = StatusFileDecoder.parseISO8601("2026-01-01T00:11:00Z")!
        let found = StatusDirectorySource.scan(directory: dir, now: now, staleAfter: 300,
                                               isAlive: { $0 == 1 }, pruneDead: true)
        #expect(Set(found.map(\.sessionID)) == ["alive", "fresh"])
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("dead.json").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("stale.json").path))
    }

    @Test func directoryResolutionMatchesReporter() {
        let url = StatusDirectorySource.defaultDirectory(environment: ["AGENT_COMPANION_DIR": "/tmp/ac"])
        #expect(url.path == "/tmp/ac/sessions")
    }
}

@MainActor
@Suite struct SessionStoreTests {
    @Test func mergesSources() {
        let a = StaticSessionSource([session("1", .working)])
        let b = StaticSessionSource([session("2", .idle)])
        let store = SessionStore(sources: [a, b])
        store.start()
        #expect(store.sessions.map(\.sessionID).sorted() == ["1", "2"])
    }
}

@Suite struct PersistentContentTests {
    @Test func usageKeepsTabVisibleWithoutSessions() {
        var p = PanelPresentation()
        p.update(sessions: [])
        #expect(p.mode == .hidden)
        p.setPersistentContent(true)
        #expect(p.mode == .collapsed)
        p.setHovering(true)
        #expect(p.mode == .expanded)
        p.setHovering(false)
        p.setPersistentContent(false)
        #expect(p.mode == .hidden)
    }
}

@MainActor
@Suite struct SessionFilterTests {
    @Test func hiddenAgentsAreFilteredButStillSeen() {
        let a = AgentSession(agent: .init(id: "pi", name: "pi"), sessionID: "1", cwd: "/", status: .working)
        let b = AgentSession(agent: .init(id: "codex", name: "Codex"), sessionID: "2", cwd: "/", status: .working)
        let store = SessionStore(sources: [StaticSessionSource([a, b])])
        store.setHiddenAgents(["codex"])
        store.start()
        #expect(store.sessions.map(\.agent.id) == ["pi"])
        #expect(Set(store.seenAgents.map(\.id)) == ["pi", "codex"])
        store.setHiddenAgents([])
        #expect(store.sessions.count == 2)
    }
}
