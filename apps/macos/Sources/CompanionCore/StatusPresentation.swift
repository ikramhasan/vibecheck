import Foundation

public struct StatusPresentation: Equatable, Sendable {
    public enum Tint: Equatable, Sendable { case accent, attention, success, muted, limited, failure }
    public enum Orb: Equatable, Sendable { case working, waiting, retrying, resting }

    public var word: String
    public var tint: Tint
    public var orb: Orb
    public var urgency: Int

    public init(_ session: AgentSession) {
        switch session.status {
        case .needsAttention:
            word = Self.attentionWord(session.attention?.kind)
            tint = .attention
            orb = .waiting
            urgency = 0
        case .error:
            word = "Failed"
            tint = .failure
            orb = .resting
            urgency = 1
        case .blocked:
            word = "Blocked"
            tint = .limited
            orb = .retrying
            urgency = 2
        case .working:
            word = "Working"
            tint = .accent
            orb = .working
            urgency = 3
        case .idle:
            word = session.wasInterrupted ? "Interrupted" : "Your turn"
            tint = session.wasInterrupted ? .muted : .success
            orb = .resting
            urgency = 4
        }
    }

    public static let leastUrgent = 4

    public static func task(_ session: AgentSession) -> String {
        session.task ?? session.name ?? "New session"
    }

    public static func headline(_ session: AgentSession) -> String {
        session.status == .needsAttention ? session.attention?.message ?? "Needs your attention" : task(session)
    }

    public static func detail(_ session: AgentSession) -> String? {
        switch session.status {
        case .needsAttention: task(session)
        case .working, .blocked, .error: [StatusPresentation(session).word, session.activity].compactMap { $0 }.joined(separator: " · ")
        case .idle: nil
        }
    }

    private static func attentionWord(_ kind: AgentSession.Attention.Kind?) -> String {
        switch kind {
        case .permission: "Waiting for approval"
        case .question: "Asking"
        case .input: "Needs input"
        case .other, nil: "Needs you"
        }
    }
}
