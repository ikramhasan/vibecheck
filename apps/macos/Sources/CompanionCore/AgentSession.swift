import Foundation

/// Agent-neutral view of one live agent session. Every integration (pi, Claude Code,
/// Codex, …) is normalised into this; nothing downstream knows which agent produced it.
public struct AgentSession: Identifiable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case working
        case needsAttention = "needs_attention"
        case idle
        case blocked
        case error
    }

    public struct Attention: Hashable, Codable, Sendable {
        public enum Kind: String, Codable, Sendable { case question, permission, input, other }
        public var kind: Kind
        public var message: String
        public var questions: [Question]

        public init(kind: Kind, message: String, questions: [Question] = []) {
            self.kind = kind
            self.message = message
            self.questions = questions
        }

        private enum CodingKeys: String, CodingKey { case kind, message, questions }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(kind: try c.decode(Kind.self, forKey: .kind), message: try c.decode(String.self, forKey: .message),
                      questions: (try? c.decodeIfPresent([Question].self, forKey: .questions)) ?? [])
        }
    }

    public struct Question: Hashable, Codable, Sendable {
        public struct Option: Hashable, Codable, Sendable {
            public var label: String
            public var description: String?

            public init(label: String, description: String? = nil) {
                self.label = label
                self.description = description
            }
        }

        public var header: String?
        public var question: String
        public var options: [Option]
        public var multiSelect: Bool

        public init(header: String? = nil, question: String, options: [Option] = [], multiSelect: Bool = false) {
            self.header = header
            self.question = question
            self.options = options
            self.multiSelect = multiSelect
        }

        private enum CodingKeys: String, CodingKey { case header, question, options, multiSelect }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(header: try? c.decodeIfPresent(String.self, forKey: .header),
                      question: try c.decode(String.self, forKey: .question),
                      options: (try? c.decodeIfPresent([Option].self, forKey: .options)) ?? [],
                      multiSelect: (try? c.decodeIfPresent(Bool.self, forKey: .multiSelect)) ?? false)
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

    public struct ContextUsage: Hashable, Sendable {
        public var usedTokens: Int
        public var windowTokens: Int

        public init(usedTokens: Int, windowTokens: Int) {
            self.usedTokens = usedTokens
            self.windowTokens = windowTokens
        }

        public enum Level: Sendable { case normal, warning, critical }

        public var fraction: Double { windowTokens > 0 ? Double(usedTokens) / Double(windowTokens) : 0 }

        public var level: Level {
            switch fraction {
            case 0.9...: .critical
            case 0.75...: .warning
            default: .normal
            }
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

    /// Globally unique: agent id + agent session id, plus the machine for remote sessions.
    public var id: String { host.map { "\(agent.id)/\(sessionID)@\($0)" } ?? "\(agent.id)/\(sessionID)" }

    public var agent: AgentInfo
    public var sessionID: String
    public var cwd: String
    /// The ssh host the agent runs on; `nil` for this Mac. Remote sessions have no local `pid`.
    public var host: String?
    public var name: String?
    public var model: String?
    public var pid: Int32?
    /// For a remote session, the ssh process on this Mac that carries it. Jumping goes through it.
    public var sshPID: Int32?
    public var origin: Origin?
    public var status: Status
    public var task: String?
    public var lastReply: String?
    public var activity: String?
    public var attention: Attention?
    public var context: ContextUsage?
    public var wasInterrupted: Bool
    public var startedAt: Date?
    public var updatedAt: Date
    /// When `status` last changed, as observed by the app (set by `SessionStore`).
    public var statusSince: Date?
    public init(agent: AgentInfo, sessionID: String, cwd: String, name: String? = nil,
                model: String? = nil, pid: Int32? = nil, origin: Origin? = nil, status: Status, task: String? = nil,
                lastReply: String? = nil, activity: String? = nil, attention: Attention? = nil, context: ContextUsage? = nil,
                wasInterrupted: Bool = false, startedAt: Date? = nil, updatedAt: Date = .now) {
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        self.name = name
        self.model = model
        self.pid = pid
        self.origin = origin
        self.status = status
        self.task = task
        self.lastReply = lastReply
        self.activity = activity
        self.attention = attention
        self.context = context
        self.wasInterrupted = wasInterrupted
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
