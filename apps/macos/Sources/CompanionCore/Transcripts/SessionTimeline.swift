import Foundation

public struct SessionTimeline: Equatable, Sendable {
    public private(set) var status: AgentSession.Status = .idle
    public private(set) var activity: String?
    public private(set) var attention: AgentSession.Attention?
    public private(set) var task: String?
    public private(set) var lastReply: String?
    public private(set) var title: String?
    public private(set) var model: String?
    public private(set) var context: AgentSession.ContextUsage?
    public private(set) var wasInterrupted = false
    public private(set) var hasEvents = false
    private var titleIsGenerated = true
    private var pending: [ToolCall] = []

    static let claudeWindow = 1_000_000
    static let legacyClaudeWindow = 200_000
    static let legacyClaudeModels = [
        "claude-3", "claude-opus-4-0", "claude-sonnet-4-0", "claude-opus-4-2025", "claude-sonnet-4-2025",
        "claude-opus-4-1", "claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5",
    ]

    public init() {}

    public mutating func apply(_ events: [TranscriptEvent]) {
        events.forEach { apply($0) }
    }

    public mutating func apply(_ event: TranscriptEvent) {
        hasEvents = true
        switch event {
        case .userPrompt(let text):
            task = TranscriptText.oneLine(text) ?? task
            lastReply = nil
            startWorking(activity: text.hasPrefix("/compact") ? "Compacting…" : "Thinking…")
        case .latestPrompt(let text):
            if task == nil { task = TranscriptText.oneLine(text) }
        case .turnStarted:
            startWorking(activity: "Thinking…")
        case .thinking:
            continueWorking(activity: "Thinking…")
        case .assistantText(let text):
            lastReply = TranscriptText.oneLine(text) ?? lastReply
            continueWorking(activity: "Writing a response…")
        case .toolCall(let call):
            pending.append(call)
            wasInterrupted = false
            showPending()
        case .toolResult(let id):
            pending.removeAll { $0.id == id }
            if pending.isEmpty { continueWorking(activity: "Thinking…") } else { showPending() }
        case .turnEnded:
            settle(.idle)
        case .interrupted:
            settle(.idle)
            wasInterrupted = true
        case .limitReached(let message):
            settle(.blocked)
            activity = TranscriptText.oneLine(message)
        case .failed(let message):
            settle(.error)
            activity = TranscriptText.oneLine(message)
        case .compacted:
            context = nil
        case .model(let name):
            model = name
        case .title(let text, let generated):
            guard generated == false || titleIsGenerated else { return }
            title = TranscriptText.oneLine(text)
            titleIsGenerated = generated
        case .contextUsage(let used, let window):
            let window = window ?? Self.claudeWindow(model: model, usedTokens: used)
            context = .init(usedTokens: used, windowTokens: window)
        }
    }

    static func claudeWindow(model: String?, usedTokens: Int) -> Int {
        let isLegacy = model.map { model in legacyClaudeModels.contains { model.contains($0) } } ?? false
        return isLegacy && usedTokens <= legacyClaudeWindow ? legacyClaudeWindow : claudeWindow
    }

    private mutating func startWorking(activity: String) {
        pending = []
        wasInterrupted = false
        status = .working
        attention = nil
        self.activity = activity
    }

    private mutating func continueWorking(activity: String) {
        wasInterrupted = false
        guard pending.isEmpty else { return showPending() }
        status = .working
        attention = nil
        self.activity = activity
    }

    private mutating func settle(_ status: AgentSession.Status) {
        pending = []
        self.status = status
        attention = nil
        activity = nil
        wasInterrupted = false
    }

    private mutating func showPending() {
        guard let call = pending.last(where: { $0.kind == .question }) ?? pending.last else { return }
        activity = Self.describe(call)
        if call.kind == .question {
            status = .needsAttention
            attention = .init(kind: .question, message: call.subject ?? "Waiting for your answer", questions: call.questions)
        } else {
            status = .working
            attention = nil
        }
    }

    static func describe(_ call: ToolCall) -> String {
        let subject = call.subject.flatMap { TranscriptText.oneLine($0, max: 80) }
        switch call.kind {
        case .read: return "Reading \(subject.map(fileName) ?? "a file")"
        case .edit: return "Editing \(subject.map(fileName) ?? "a file")"
        case .run: return "Running \(subject ?? "a command")"
        case .search: return "Searching \(subject ?? "the code")"
        case .fetch: return "Fetching \(subject ?? "a page")"
        case .plan: return "Planning"
        case .delegate: return subject.map { "Delegating: \($0)" } ?? "Delegating to a subagent"
        case .question: return "Asking you"
        case .other: return "Using \(call.name)"
        }
    }

    private static func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
