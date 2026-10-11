import Foundation

public struct CompletedFilter: Equatable, Sendable {
    private var cleared: [String: Date] = [:]

    public init() {}

    public static func isCompleted(_ session: AgentSession) -> Bool {
        session.status == .idle
    }

    public func isCleared(_ session: AgentSession) -> Bool {
        Self.isCompleted(session) && cleared[session.id] == Self.since(session)
    }

    public func preview(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions.filter { !isCleared($0) }
    }

    public func clearableCount(_ sessions: [AgentSession]) -> Int {
        sessions.filter { Self.isCompleted($0) && !isCleared($0) }.count
    }

    public mutating func clear(_ sessions: [AgentSession]) {
        for session in sessions where Self.isCompleted(session) {
            cleared[session.id] = Self.since(session)
        }
    }

    public mutating func forgetResumed(_ sessions: [AgentSession]) {
        let stillCleared = Set(sessions.filter(isCleared).map(\.id))
        cleared = cleared.filter { stillCleared.contains($0.key) }
    }

    private static func since(_ session: AgentSession) -> Date {
        session.statusSince ?? session.updatedAt
    }
}
