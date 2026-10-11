import Foundation
import Testing
@testable import CompanionCore

@Suite struct SoundSettingsTests {
    @Test func defaultsUntilChanged() {
        var s = SoundSettings()
        #expect(s.sound(for: .needsInput) == "Ping")
        #expect(s.sound(for: .finished) == "Glass")
        #expect(s.sound(for: .failed) == "Basso")
        s.setSound(nil, for: .finished)
        s.setSound("Hero", for: .failed)
        #expect(s.sound(for: .finished) == nil)
        #expect(s.sound(for: .failed) == "Hero")
    }

    @Test func roundTripsThroughJSONIncludingNone() throws {
        var s = SoundSettings(volume: 0.4)
        s.setSound(nil, for: .needsInput)
        s.setSound("Tink", for: .finished)
        let decoded = try JSONDecoder().decode(SoundSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
        #expect(decoded.sound(for: .needsInput) == nil)
        #expect(decoded.sound(for: .failed) == "Basso")
    }

    @Test func unknownEventsAreDropped() throws {
        let json = #"{"sounds":{"gone":"Pop","finished":"Pop"}}"#
        let s = try JSONDecoder().decode(SoundSettings.self, from: Data(json.utf8))
        #expect(s.sound(for: .finished) == "Pop")
        #expect(s.volume == SoundSettings.default.volume)
    }
}

@Suite struct SoundPlannerTests {
    private let launch = Date(timeIntervalSince1970: 1000)

    private func session(_ status: AgentSession.Status, at time: TimeInterval, id: String = "1",
                         message: String? = nil, interrupted: Bool = false) -> AgentSession {
        var s = AgentSession(agent: .init(id: "claude", name: "Claude"), sessionID: id, cwd: "/repo",
                             status: status, attention: message.map { .init(kind: .question, message: $0) },
                             wasInterrupted: interrupted)
        s.statusSince = Date(timeIntervalSince1970: time)
        return s
    }

    private func at(_ time: TimeInterval) -> Date { Date(timeIntervalSince1970: time) }

    @Test func needsInputPlaysOncePerQuestion() {
        var planner = SoundPlanner(launchedAt: launch)
        #expect(planner.update([session(.working, at: 1001)], now: at(1001)) == [])
        #expect(planner.update([session(.needsAttention, at: 1010, message: "A?")], now: at(1010)) == [.needsInput])
        #expect(planner.update([session(.needsAttention, at: 1010, message: "A?")], now: at(1020)) == [])
        #expect(planner.update([session(.needsAttention, at: 1010, message: "B?")], now: at(1030)) == [.needsInput])
    }

    @Test func finishedOnlyAfterWorkingAndNotAfterInterrupt() {
        var planner = SoundPlanner(launchedAt: launch)
        #expect(planner.update([session(.idle, at: 1001)], now: at(1001)) == [])
        _ = planner.update([session(.working, at: 1002)], now: at(1002))
        #expect(planner.update([session(.idle, at: 1005)], now: at(1005)) == [.finished])
        #expect(planner.update([session(.idle, at: 1005)], now: at(1010)) == [])
        _ = planner.update([session(.working, at: 1020)], now: at(1020))
        #expect(planner.update([session(.idle, at: 1025, interrupted: true)], now: at(1025)) == [])
    }

    @Test func failuresPlayOnEnteringBlockedOrError() {
        var planner = SoundPlanner(launchedAt: launch)
        _ = planner.update([session(.working, at: 1001)], now: at(1001))
        #expect(planner.update([session(.error, at: 1005)], now: at(1005)) == [.failed])
        #expect(planner.update([session(.error, at: 1005)], now: at(1010)) == [])
        #expect(planner.update([session(.blocked, at: 1020)], now: at(1020)) == [.failed])
    }

    @Test func statesOlderThanLaunchStayQuiet() {
        var planner = SoundPlanner(launchedAt: launch)
        #expect(planner.update([session(.needsAttention, at: 900, message: "Old?"),
                                session(.blocked, at: 900, id: "2")], now: at(1001)) == [])
    }

    @Test func burstPlaysOncePerTypeWithinThrottle() {
        var planner = SoundPlanner(launchedAt: launch)
        _ = planner.update([session(.working, at: 1001, id: "1"), session(.working, at: 1001, id: "2"),
                            session(.working, at: 1001, id: "3")], now: at(1001))
        #expect(planner.update([session(.idle, at: 1005, id: "1"), session(.idle, at: 1005, id: "2"),
                                session(.working, at: 1001, id: "3")], now: at(1005)) == [.finished])
        #expect(planner.update([session(.idle, at: 1005, id: "1"), session(.idle, at: 1005, id: "2"),
                                session(.idle, at: 1006, id: "3")], now: at(1006)) == [])
        _ = planner.update([session(.working, at: 1010, id: "1")], now: at(1010))
        #expect(planner.update([session(.idle, at: 1012, id: "1")], now: at(1012)) == [.finished])
    }

    @Test func differentTypesInOneBurstEachPlay() {
        var planner = SoundPlanner(launchedAt: launch)
        _ = planner.update([session(.working, at: 1001, id: "1"), session(.working, at: 1001, id: "2")], now: at(1001))
        #expect(planner.update([session(.idle, at: 1005, id: "1"), session(.error, at: 1005, id: "2")],
                               now: at(1005)) == [.finished, .failed])
    }
}
