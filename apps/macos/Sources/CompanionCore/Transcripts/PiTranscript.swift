import Foundation

// Session format ported from agentsview (MIT, github.com/kenn-io/agentsview), internal/parser/pi.go.
public enum PiTranscript {
    public static func events(from line: Data) -> [TranscriptEvent] {
        guard let entry = TranscriptText.json(line) else { return [] }
        switch entry["type"] as? String {
        case "message": return (entry["message"] as? [String: Any]).map(messageEvents) ?? []
        case "model_change": return TranscriptText.string(entry["modelId"]).map { [.model($0)] } ?? []
        case "session_info": return TranscriptText.string(entry["name"]).map { [.title($0, generated: false)] } ?? []
        case "compaction": return [.compacted]
        default: return []
        }
    }

    private static func messageEvents(_ message: [String: Any]) -> [TranscriptEvent] {
        let blocks = message["content"] as? [[String: Any]] ?? []
        switch message["role"] as? String {
        case "user":
            let text = (message["content"] as? String) ?? blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
            return [.userPrompt(text)]
        case "toolResult":
            return TranscriptText.string(message["toolCallId"]).map { [.toolResult(id: $0)] } ?? []
        case "assistant":
            return assistantEvents(message, blocks)
        default:
            return []
        }
    }

    private static func assistantEvents(_ message: [String: Any], _ blocks: [[String: Any]]) -> [TranscriptEvent] {
        var events: [TranscriptEvent] = []
        if let model = TranscriptText.string(message["model"]) { events.append(.model(model)) }
        if let usage = contextUsage(message["usage"] as? [String: Any]) { events.append(usage) }
        for block in blocks {
            switch block["type"] as? String {
            case "thinking": events.append(.thinking)
            case "text": events.append(.assistantText(block["text"] as? String ?? ""))
            case "toolCall":
                guard let id = TranscriptText.string(block["id"]), let name = TranscriptText.string(block["name"]) else { continue }
                let (kind, subject) = classify(name, block["arguments"] as? [String: Any] ?? [:])
                events.append(.toolCall(ToolCall(id: id, name: name, kind: kind, subject: subject)))
            default: break
            }
        }
        let error = TranscriptText.string(message["errorMessage"]) ?? "Run failed"
        switch message["stopReason"] as? String {
        case "stop", "length": events.append(.turnEnded)
        case "aborted": events.append(.interrupted)
        case "error": events.append(errorEvent(error))
        default: break
        }
        return events
    }

    private static func errorEvent(_ message: String) -> TranscriptEvent {
        let lower = message.lowercased()
        if lower.contains("operation was aborted") { return .interrupted }
        if ["rate limit", "usage limit", "quota", "429"].contains(where: lower.contains) { return .limitReached(message) }
        return .failed(message)
    }

    private static func contextUsage(_ usage: [String: Any]?) -> TranscriptEvent? {
        guard let usage, let percent = usage["contextPercent"] as? Double, percent > 0 else { return nil }
        let used = ["input", "cacheRead", "cacheWrite"].reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
        guard used > 0 else { return nil }
        return .contextUsage(usedTokens: used, windowTokens: Int((Double(used) * 100 / percent).rounded()))
    }

    static func classify(_ name: String, _ input: [String: Any]) -> (ToolCall.Kind, String?) {
        switch name {
        case "read": return (.read, TranscriptText.firstString(input, ["path"]))
        case "write", "edit": return (.edit, TranscriptText.firstString(input, ["path"]))
        case "bash": return (.run, TranscriptText.firstString(input, ["command"]))
        case "codemode": return (.run, "a script")
        case "grep", "find", "ls": return (.search, TranscriptText.firstString(input, ["pattern", "path"]))
        case "web_search": return (.fetch, TranscriptText.firstString(input, ["query"]))
        case "fetch_content": return (.fetch, TranscriptText.firstString(input, ["url"]))
        case "subagent": return (.delegate, nil)
        default: return (.other, nil)
        }
    }
}
