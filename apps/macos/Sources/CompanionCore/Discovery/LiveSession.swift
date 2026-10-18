import Foundation

public enum TranscriptFormat: Sendable {
    case claude, codex, pi

    public func events(from line: Data) -> [TranscriptEvent] {
        switch self {
        case .claude: ClaudeTranscript.events(from: line)
        case .codex: CodexTranscript.events(from: line)
        case .pi: PiTranscript.events(from: line)
        }
    }
}

public struct LiveSession: Equatable, Sendable {
    public var agent: AgentSession.AgentInfo
    public var sessionID: String
    public var format: TranscriptFormat
    public var transcript: URL?
    public var pid: Int32
    public var cwd: String
    public var name: String?
    public var origin: AgentSession.Origin?
    public var startedAt: Date?
    public var statusWithoutTranscript: AgentSession.Status
    public var idleSince: Date?

    public init(agent: AgentSession.AgentInfo, sessionID: String, format: TranscriptFormat, transcript: URL?,
                pid: Int32, cwd: String, name: String? = nil, origin: AgentSession.Origin? = nil,
                startedAt: Date? = nil, statusWithoutTranscript: AgentSession.Status = .idle, idleSince: Date? = nil) {
        self.agent = agent
        self.sessionID = sessionID
        self.format = format
        self.transcript = transcript
        self.pid = pid
        self.cwd = cwd
        self.name = name
        self.origin = origin
        self.startedAt = startedAt
        self.statusWithoutTranscript = statusWithoutTranscript
        self.idleSince = idleSince
    }

    public var id: String { "\(agent.id)/\(sessionID)" }
}

public enum AgentIdentity {
    public static let claude = AgentSession.AgentInfo(id: "claude", name: "Claude")
    public static let codex = AgentSession.AgentInfo(id: "codex", name: "Codex")
    public static let pi = AgentSession.AgentInfo(id: "pi", name: "pi")
}
