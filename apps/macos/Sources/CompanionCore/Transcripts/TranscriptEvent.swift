import Foundation

public enum TranscriptEvent: Equatable, Sendable {
    case userPrompt(String)
    case latestPrompt(String)
    case turnStarted
    case thinking
    case assistantText(String)
    case toolCall(ToolCall)
    case toolResult(id: String)
    case backgroundStarted(BackgroundTask)
    case backgroundEnded(ids: [String])
    case turnEnded
    case interrupted
    case limitReached(String)
    case failed(String)
    case compacted
    case model(String)
    case title(String, generated: Bool)
    case contextUsage(usedTokens: Int, windowTokens: Int?)
    case timestamp(Date)
}

public struct ToolCall: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case read, edit, run, search, fetch, plan, delegate, question, other }

    public var id: String
    public var name: String
    public var kind: Kind
    public var subject: String?
    public var questions: [AgentSession.Question]

    public init(id: String, name: String, kind: Kind, subject: String? = nil, questions: [AgentSession.Question] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.subject = subject
        self.questions = questions
    }
}

public struct BackgroundTask: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case command, monitor, agent }

    public var id: String
    public var kind: Kind

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

enum TranscriptText {
    static func oneLine(_ text: String?, max: Int = 160) -> String? {
        guard let text else { return nil }
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        return flat.count > max ? String(flat.prefix(max - 1)) + "…" : flat
    }

    static func string(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    static func json(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    static func jsonObject(string: String?) -> [String: Any]? {
        guard let data = string?.data(using: .utf8) else { return nil }
        return json(data)
    }

    static func firstString(_ input: [String: Any], _ keys: [String]) -> String? {
        keys.lazy.compactMap { string(input[$0]) }.first
    }

    static func questions(_ input: [String: Any]) -> [AgentSession.Question] {
        (input["questions"] as? [[String: Any]] ?? []).compactMap { item in
            guard let text = string(item["question"]) else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option in
                string(option["label"]).map { AgentSession.Question.Option(label: $0, description: string(option["description"])) }
            }
            return AgentSession.Question(header: string(item["header"]), question: text, options: options,
                                         multiSelect: item["multiSelect"] as? Bool ?? false)
        }
    }
}
