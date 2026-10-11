import Foundation
import Testing
@testable import CompanionCore

@Suite struct CompletedFilterTests {
    private func session(_ id: String, _ status: AgentSession.Status, since: TimeInterval) -> AgentSession {
        var s = AgentSession(agent: .init(id: "claude", name: "Claude"), sessionID: id, cwd: "/", status: status)
        s.statusSince = Date(timeIntervalSince1970: since)
        return s
    }

    @Test func clearsOnlyCompletedSessions() {
        let sessions = [session("done", .idle, since: 1), session("busy", .working, since: 1),
                        session("asking", .needsAttention, since: 1), session("stuck", .blocked, since: 1),
                        session("broken", .error, since: 1)]
        var filter = CompletedFilter()
        #expect(filter.clearableCount(sessions) == 1)
        filter.clear(sessions)
        #expect(filter.preview(sessions).map(\.sessionID) == ["busy", "asking", "stuck", "broken"])
        #expect(filter.clearableCount(sessions) == 0)
    }

    @Test func sessionReturnsWhenItFinishesAnotherTurn() {
        var filter = CompletedFilter()
        filter.clear([session("a", .idle, since: 1)])
        let working = [session("a", .working, since: 2)]
        filter.forgetResumed(working)
        #expect(filter.preview(working).count == 1)
        let doneAgain = [session("a", .idle, since: 3)]
        filter.forgetResumed(doneAgain)
        #expect(filter.preview(doneAgain).count == 1)
        #expect(filter.clearableCount(doneAgain) == 1)
    }
}

@Suite struct ClearedPreviewPresentationTests {
    private let idle = AgentSession(agent: .init(id: "a", name: "A"), sessionID: "1", cwd: "/", status: .idle)

    @Test func hidesOnceEverythingIsClearedAndPointerLeaves() {
        var p = PanelPresentation()
        p.update(sessions: [idle])
        p.setHovering(true)
        p.update(sessions: [idle], previewCount: 0)
        #expect(p.mode == .expanded)
        p.setHovering(false)
        #expect(p.mode == .hidden)
    }

    @Test func usageKeepsTabWhenEverythingIsCleared() {
        var p = PanelPresentation()
        p.setPersistentContent(true)
        p.update(sessions: [idle], previewCount: 0)
        #expect(p.mode == .collapsed)
    }
}
