import Foundation

public struct SessionAlert: Equatable, Sendable {
    public var sessionID: String
    public var title: String
    public var body: String
    public var fireAt: Date
}

public enum AlertAction: Equatable, Sendable {
    case post(SessionAlert)
    case withdraw(sessionID: String)
}

public struct AlertPlanner: Sendable {
    private let launchedAt: Date
    private var active: [String: String] = [:]
    private var previousStatus: [String: AgentSession.Status] = [:]

    public init(launchedAt: Date = .now) {
        self.launchedAt = launchedAt
    }

    public mutating func update(_ sessions: [AgentSession], settings: AlertSettings,
                                projectName: (String) -> String) -> [AlertAction] {
        var actions: [AlertAction] = []
        let current = Set(sessions.map(\.id))
        for id in active.keys where !current.contains(id) {
            actions.append(.withdraw(sessionID: id))
            active[id] = nil
        }
        for session in sessions {
            let key = alertKey(session, settings: settings)
            previousStatus[session.id] = session.status
            guard key != active[session.id] else { continue }
            if active[session.id] != nil { actions.append(.withdraw(sessionID: session.id)) }
            active[session.id] = key
            guard key != nil else { continue }
            let since = session.statusSince ?? session.updatedAt
            actions.append(.post(alert(session, project: projectName(session.cwd),
                                       fireAt: since.addingTimeInterval(TimeInterval(settings.delaySeconds)))))
        }
        previousStatus = previousStatus.filter { current.contains($0.key) }
        return actions
    }

    private func alertKey(_ session: AgentSession, settings: AlertSettings) -> String? {
        let since = session.statusSince ?? session.updatedAt
        switch session.status {
        case .needsAttention where settings.needsInput && since >= launchedAt:
            return "attention|\(session.attentionKey ?? "")"
        case .idle where settings.finished && !session.wasInterrupted:
            if let current = active[session.id], current.hasPrefix("finished|") { return current }
            return previousStatus[session.id] == .working ? "finished|\(since.timeIntervalSince1970)" : nil
        case .blocked, .error:
            guard settings.problems, since >= launchedAt else { return nil }
            return "problem|\(session.status.rawValue)|\(session.activity ?? "")"
        default:
            return nil
        }
    }

    private func alert(_ session: AgentSession, project: String, fireAt: Date) -> SessionAlert {
        let agent = session.agent.name
        let (headline, body): (String, String) = switch session.status {
        case .needsAttention: ("\(agent) needs input", StatusPresentation.headline(session))
        case .blocked: ("\(agent) is blocked", session.activity ?? StatusPresentation.task(session))
        case .error: ("\(agent) failed", session.activity ?? StatusPresentation.task(session))
        default: ("\(agent) finished", StatusPresentation.task(session))
        }
        return SessionAlert(sessionID: session.id, title: "\(headline) · \(project)", body: body, fireAt: fireAt)
    }
}
