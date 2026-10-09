import Foundation
import Observation

/// Merges every registered `SessionSource` into one list for the UI.
/// Adding an agent = adding a source (or, usually, nothing at all: reporter-based
/// agents all arrive through the single `StatusDirectorySource`).
@MainActor
@Observable
public final class SessionStore {
    public private(set) var sessions: [AgentSession] = []

    @ObservationIgnored private var sources: [SessionSource] = []
    @ObservationIgnored private var bySource: [ObjectIdentifier: [AgentSession]] = [:]
    /// Agent ids the user turned running status off for (Settings).
    @ObservationIgnored private var hiddenAgents: Set<String> = []
    /// Notified after `sessions` changes (used by AppKit code that isn't SwiftUI).
    @ObservationIgnored public var onChange: (([AgentSession]) -> Void)?

    public init(sources: [SessionSource]) {
        sources.forEach(add)
    }

    public func add(_ source: SessionSource) {
        sources.append(source)
        let key = ObjectIdentifier(source)
        source.onChange = { [weak self] sessions in
            self?.bySource[key] = sessions
            self?.recompute()
        }
    }

    /// Every agent seen so far, including hidden ones, so Settings can list them.
    public private(set) var seenAgents: [AgentSession.AgentInfo] = []

    public func setHiddenAgents(_ ids: Set<String>) {
        guard ids != hiddenAgents else { return }
        hiddenAgents = ids
        recompute()
    }

    public func start() { sources.forEach { $0.start() } }
    public func stop() { sources.forEach { $0.stop() } }

    private func recompute() {
        var merged: [String: AgentSession] = [:]
        for list in bySource.values {
            for s in list where !seenAgents.contains(where: { $0.id == s.agent.id }) {
                seenAgents.append(s.agent)
            }
            for s in list where !hiddenAgents.contains(s.agent.id) && (merged[s.id]?.updatedAt ?? .distantPast) <= s.updatedAt {
                merged[s.id] = s
            }
        }
        let previous = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let next = merged.values.map { s -> AgentSession in
            var s = s
            if let old = previous[s.id], old.status == s.status {
                s.statusSince = old.statusSince
            } else {
                // Status changed, or first sighting: the last report is the best guess.
                s.statusSince = s.updatedAt
            }
            return s
        }.sorted {
            ($0.startedAt ?? $0.updatedAt, $0.id) < ($1.startedAt ?? $1.updatedAt, $1.id)
        }
        guard next != sessions else { return }
        sessions = next
        onChange?(next)
    }
}

/// Fixed sessions, for `--demo` and previews.
@MainActor
public final class StaticSessionSource: SessionSource {
    public var onChange: (([AgentSession]) -> Void)?
    private let sessions: [AgentSession]

    public init(_ sessions: [AgentSession]) { self.sessions = sessions }
    public func start() { onChange?(sessions) }
    public func stop() {}
}
