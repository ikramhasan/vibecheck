import Foundation

public enum TranscriptEvent: Equatable, Sendable {
    case userPrompt(String)
    case latestPrompt(String)
    case turnStarted
    case thinking
    case assistantText(String)
    case toolCall(ToolCall)
    case toolResult(id: String)
    case turnEnded
    case interrupted
    case limitReached(String)
    case failed(String)
    case compacted
    case model(String)
    case title(String, generated: Bool)
    case contextUsage(usedTokens: Int, windowTokens: Int?)
}

public struct ToolCall: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case read, edit, run, search, fetch, plan, delegate, question, other }

    public var id: String
    public var name: String
    public var kind: Kind
    public var subject: String?

    public init(id: String, name: String, kind: Kind, subject: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.subject = subject
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
}
