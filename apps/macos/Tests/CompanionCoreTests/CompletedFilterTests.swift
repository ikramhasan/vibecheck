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
        #expect(filter.visible(sessions).map(\.sessionID) == ["busy", "asking", "stuck", "broken"])
        #expect(filter.clearableCount(sessions) == 0)
    }

    @Test func sessionReturnsWhenItFinishesAnotherTurn() {
        var filter = CompletedFilter()
        filter.clear([session("a", .idle, since: 1)])
        let working = [session("a", .working, since: 2)]
        filter.forgetResumed(working)
        #expect(filter.visible(working).count == 1)
        let doneAgain = [session("a", .idle, since: 3)]
        filter.forgetResumed(doneAgain)
        #expect(filter.visible(doneAgain).count == 1)
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

@Suite struct CompletedRemovalTests {
    private func session(_ id: String, _ status: AgentSession.Status, since: TimeInterval) -> AgentSession {
        var s = AgentSession(agent: .init(id: "claude", name: "Claude"), sessionID: id, cwd: "/", status: status)
        s.statusSince = Date(timeIntervalSince1970: since)
        return s
    }

    @Test func dismissHidesOneCompletedSession() {
        var filter = CompletedFilter()
        let done = session("a", .idle, since: 1)
        let other = session("b", .idle, since: 1)
        let busy = session("c", .working, since: 1)
        filter.dismiss(done)
        filter.dismiss(busy)
        #expect(filter.visible([done, other, busy]).map(\.sessionID) == ["b", "c"])
    }

    @Test func autoClearsOnlySessionsFinishedLongEnoughAgo() {
        var filter = CompletedFilter()
        let old = session("old", .idle, since: 100)
        let recent = session("recent", .idle, since: 290)
        let busy = session("busy", .working, since: 0)
        let cutoff = Date(timeIntervalSince1970: 200)
        let first = filter.clear([old, recent, busy], finishedBefore: cutoff)
        #expect(first)
        #expect(filter.visible([old, recent, busy]).map(\.sessionID) == ["recent", "busy"])
        let again = filter.clear([old, recent, busy], finishedBefore: cutoff)
        #expect(!again)
    }

    @MainActor @Test func removalChoicesPersist() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        #expect(AppSettings(defaults: defaults).finishedSessionRemoval == .minutes5)
        AppSettings(defaults: defaults).finishedSessionRemoval = .never
        #expect(AppSettings(defaults: defaults).finishedSessionRemoval == .never)
        #expect(FinishedSessionRemoval.instant.delay == 0)
        #expect(FinishedSessionRemoval.never.delay == nil)
    }
}
