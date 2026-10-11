import Foundation
import Testing
@testable import CompanionCore

@Suite struct AlertPlannerTests {
    private let launch = Date(timeIntervalSince1970: 1000)

    private func session(_ status: AgentSession.Status, at time: TimeInterval, message: String? = nil,
                         interrupted: Bool = false, activity: String? = nil) -> AgentSession {
        var s = AgentSession(agent: .init(id: "claude", name: "Claude"), sessionID: "1", cwd: "/repo/app",
                             status: status, task: "Fix login", activity: activity,
                             attention: message.map { .init(kind: .question, message: $0) },
                             wasInterrupted: interrupted)
        s.statusSince = Date(timeIntervalSince1970: time)
        return s
    }

    private func plan(_ planner: inout AlertPlanner, _ session: AgentSession, _ settings: AlertSettings = .init()) -> [AlertAction] {
        planner.update([session], settings: settings) { ($0 as NSString).lastPathComponent }
    }

    @Test func questionPostsAfterDelayAndClearsOnResume() {
        var planner = AlertPlanner(launchedAt: launch)
        #expect(plan(&planner, session(.working, at: 1001)) == [])
        let posted = plan(&planner, session(.needsAttention, at: 1010, message: "Which DB?"))
        #expect(posted == [.post(.init(sessionID: "claude/1", title: "Claude needs input · app", body: "Which DB?",
                                       fireAt: Date(timeIntervalSince1970: 1020)))])
        #expect(plan(&planner, session(.needsAttention, at: 1010, message: "Which DB?")) == [])
        #expect(plan(&planner, session(.working, at: 1030)) == [.withdraw(sessionID: "claude/1")])
    }

    @Test func finishedOnlyAfterWorking() {
        var planner = AlertPlanner(launchedAt: launch)
        #expect(plan(&planner, session(.idle, at: 1001)) == [])
        _ = plan(&planner, session(.working, at: 1002))
        let actions = plan(&planner, session(.idle, at: 1005))
        #expect(actions.count == 1)
        guard case .post(let alert) = actions.first else { Issue.record("expected a post"); return }
        #expect(alert.title == "Claude finished · app")
        #expect(alert.body == "Fix login")
        #expect(plan(&planner, session(.idle, at: 1005)) == [])
    }

    @Test func interruptNeverNotifies() {
        var planner = AlertPlanner(launchedAt: launch)
        _ = plan(&planner, session(.working, at: 1002))
        #expect(plan(&planner, session(.idle, at: 1005, interrupted: true)) == [])
    }

    @Test func statesOlderThanLaunchStayQuiet() {
        var planner = AlertPlanner(launchedAt: launch)
        #expect(plan(&planner, session(.needsAttention, at: 900, message: "Old?")) == [])
        #expect(plan(&planner, session(.blocked, at: 900, activity: "limit")) == [])
    }

    @Test func disabledEventsDoNotPost() {
        var planner = AlertPlanner(launchedAt: launch)
        let off = AlertSettings(needsInput: false, finished: false, problems: false)
        _ = plan(&planner, session(.working, at: 1002), off)
        #expect(plan(&planner, session(.needsAttention, at: 1003, message: "Q"), off) == [])
        #expect(plan(&planner, session(.idle, at: 1004), off) == [])
    }

    @Test func endedSessionIsWithdrawn() {
        var planner = AlertPlanner(launchedAt: launch)
        _ = plan(&planner, session(.blocked, at: 1003, activity: "Session limit"))
        #expect(planner.update([], settings: .init()) { $0 } == [.withdraw(sessionID: "claude/1")])
    }
}
