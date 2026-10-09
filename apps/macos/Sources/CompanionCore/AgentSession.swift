import Foundation

/// Agent-neutral view of one live agent session. Every integration (pi, Claude Code,
/// Codex, …) is normalised into this; nothing downstream knows which agent produced it.
public struct AgentSession: Identifiable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case working
        case needsAttention = "needs_attention"
        case idle
        case error
    }

    public struct Attention: Hashable, Codable, Sendable {
        public enum Kind: String, Codable, Sendable { case question, permission, input, other }
        public var kind: Kind
        public var message: String

        public init(kind: Kind, message: String) {
            self.kind = kind
            self.message = message
        }
    }

    /// Which app the session runs in, as reported by the integration (see `SessionOrigin`).
    public struct Origin: Hashable, Codable, Sendable {
        public var bundleId: String?
        public var termProgram: String?

        public init(bundleId: String? = nil, termProgram: String? = nil) {
            self.bundleId = bundleId
            self.termProgram = termProgram
        }
    }

    public struct AgentInfo: Hashable, Codable, Sendable {
        /// Stable lowercase identifier, e.g. "pi", "claude", "codex".
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// Globally unique: agent id + agent session id.
    public var id: String { "\(agent.id)/\(sessionID)" }

    public var agent: AgentInfo
    public var sessionID: String
    public var cwd: String
    public var name: String?
    public var model: String?
    public var pid: Int32?
    public var origin: Origin?
    public var status: Status
    public var task: String?
    public var activity: String?
    public var attention: Attention?
    public var startedAt: Date?
    public var updatedAt: Date
    /// When `status` last changed, as observed by the app (set by `SessionStore`).
    public var statusSince: Date?
    public init(agent: AgentInfo, sessionID: String, cwd: String, name: String? = nil,
                model: String? = nil, pid: Int32? = nil, origin: Origin? = nil, status: Status, task: String? = nil,
                activity: String? = nil, attention: Attention? = nil, startedAt: Date? = nil,
                updatedAt: Date = .now) {
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        self.name = name
        self.model = model
        self.pid = pid
        self.origin = origin
        self.status = status
        self.task = task
        self.activity = activity
        self.attention = attention
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public var needsAttention: Bool { status == .needsAttention }

    /// Key that changes whenever a *new* request for attention appears, so the UI
    /// can re-surface a session that asks again after the user dismissed it once.
    public var attentionKey: String? {
        guard needsAttention else { return nil }
        return "\(id)|\(attention?.kind.rawValue ?? "")|\(attention?.message ?? "")"
    }
}
