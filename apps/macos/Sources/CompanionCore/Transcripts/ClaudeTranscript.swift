import Foundation

// Transcript format ported from agentsview (MIT, github.com/kenn-io/agentsview), internal/parser/claude.go.
public enum ClaudeTranscript {
    public static func events(from line: Data) -> [TranscriptEvent] {
        guard let entry = TranscriptText.json(line), entry["isSidechain"] as? Bool != true else { return [] }
        switch entry["type"] as? String {
        case "user": return timestamped(userEvents(entry), entry)
        case "assistant": return timestamped(assistantEvents(entry), entry)
        case "system": return entry["subtype"] as? String == "compact_boundary" ? [.compacted] : []
        case "custom-title": return TranscriptText.string(entry["customTitle"]).map { [.title($0, generated: false)] } ?? []
        case "ai-title": return TranscriptText.string(entry["aiTitle"]).map { [.title($0, generated: true)] } ?? []
        case "last-prompt": return TranscriptText.string(entry["lastPrompt"]).map { [.latestPrompt($0)] } ?? []
        case "queue-operation": return entry["operation"] as? String == "enqueue" ? notificationEvents(entry["content"] as? String ?? "") : []
        default: return []
        }
    }

    private static func timestamped(_ events: [TranscriptEvent], _ entry: [String: Any]) -> [TranscriptEvent] {
        guard !events.isEmpty, let raw = entry["timestamp"] as? String,
              let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw) else { return events }
        return events + [.timestamp(date)]
    }

    private static func userEvents(_ entry: [String: Any]) -> [TranscriptEvent] {
        if entry["isCompactSummary"] as? Bool == true { return [.compacted] }
        guard entry["isMeta"] as? Bool != true, let message = entry["message"] as? [String: Any] else { return [] }
        let origin = (entry["origin"] as? [String: Any])?["kind"] as? String
        let fromUser = origin == nil || origin == "human"
        if let text = message["content"] as? String {
            let startsTurn = entry["queueTranscriptOnly"] as? Bool != true
            return notificationEvents(text) + (startsTurn ? promptEvents(text, fromUser: fromUser) : [])
        }
        guard let blocks = message["content"] as? [[String: Any]] else { return [] }
        var events: [TranscriptEvent] = []
        for block in blocks {
            switch block["type"] as? String {
            case "tool_result":
                if let id = TranscriptText.string(block["tool_use_id"]) { events.append(.toolResult(id: id)) }
                events += backgroundEvents(entry["toolUseResult"] as? [String: Any] ?? [:])
            case "text":
                let text = block["text"] as? String ?? ""
                events += notificationEvents(text) + promptEvents(text, fromUser: fromUser)
            default:
                break
            }
        }
        return events
    }

    private static func backgroundEvents(_ result: [String: Any]) -> [TranscriptEvent] {
        if let id = TranscriptText.string(result["backgroundTaskId"]) { return [.backgroundStarted(.init(id: id, kind: .command))] }
        if let id = TranscriptText.string(result["taskId"]), result["persistent"] as? Bool == false {
            return [.backgroundStarted(.init(id: id, kind: .monitor))]
        }
        if result["isAsync"] as? Bool == true, let id = TranscriptText.string(result["agentId"]) {
            return [.backgroundStarted(.init(id: id, kind: .agent))]
        }
        if let id = TranscriptText.string(result["task_id"]) { return [.backgroundEnded(ids: [id])] }
        return []
    }

    private static func notificationEvents(_ text: String) -> [TranscriptEvent] {
        guard text.contains("<task-notification>"), tag("status", in: text) != nil else { return [] }
        let ids = text.components(separatedBy: "<task-id>").dropFirst().compactMap { part in
            part.components(separatedBy: "</task-id>").first.flatMap(TranscriptText.string)
        }
        return ids.isEmpty ? [] : [.backgroundEnded(ids: ids)]
    }

    private static func promptEvents(_ text: String, fromUser: Bool) -> [TranscriptEvent] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[Request interrupted by user") { return [.interrupted] }
        guard fromUser else { return [.turnStarted] }
        if trimmed.isEmpty || ["<local-command", "<bash-stdout", "<system-reminder>"].contains(where: trimmed.hasPrefix) { return [] }
        if let command = slashCommand(trimmed) { return [.userPrompt(command)] }
        return [.userPrompt(trimmed)]
    }

    private static func slashCommand(_ text: String) -> String? {
        guard text.hasPrefix("<command-"), let name = tag("command-name", in: text) else { return nil }
        let args = tag("command-args", in: text) ?? ""
        return args.isEmpty ? name : "\(name) \(args)"
    }

    private static func tag(_ name: String, in text: String) -> String? {
        guard let open = text.range(of: "<\(name)>"),
              let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex) else { return nil }
        return String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func assistantEvents(_ entry: [String: Any]) -> [TranscriptEvent] {
        guard let message = entry["message"] as? [String: Any] else { return [] }
        let blocks = message["content"] as? [[String: Any]] ?? []
        if entry["isApiErrorMessage"] as? Bool == true {
            let text = blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
            let reason = text.isEmpty ? "API error" : text
            return [entry["error"] as? String == "rate_limit" ? .limitReached(reason) : .failed(reason)]
        }
        var events: [TranscriptEvent] = []
        if let model = TranscriptText.string(message["model"]), model != "<synthetic>" { events.append(.model(model)) }
        if let usage = message["usage"] as? [String: Any] {
            let used = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                .reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
            if used > 0 { events.append(.contextUsage(usedTokens: used, windowTokens: nil)) }
        }
        for block in blocks {
            switch block["type"] as? String {
            case "thinking", "redacted_thinking": events.append(.thinking)
            case "text": events.append(.assistantText(block["text"] as? String ?? ""))
            case "tool_use": if let call = toolCall(block) { events.append(.toolCall(call)) }
            default: break
            }
        }
        switch message["stop_reason"] as? String {
        case "end_turn", "max_tokens", "stop_sequence", "refusal": events.append(.turnEnded)
        default: break
        }
        return events
    }

    private static func toolCall(_ block: [String: Any]) -> ToolCall? {
        guard let id = TranscriptText.string(block["id"]), let name = TranscriptText.string(block["name"]) else { return nil }
        let input = block["input"] as? [String: Any] ?? [:]
        let (kind, subject) = classify(name, input)
        return ToolCall(id: id, name: name, kind: kind, subject: subject,
                            questions: kind == .question ? TranscriptText.questions(input) : [])
    }

    static func classify(_ name: String, _ input: [String: Any]) -> (ToolCall.Kind, String?) {
        switch name {
        case "Read", "NotebookRead":
            return (.read, TranscriptText.firstString(input, ["file_path", "notebook_path", "path"]))
        case "Write", "Edit", "MultiEdit", "NotebookEdit":
            return (.edit, TranscriptText.firstString(input, ["file_path", "notebook_path", "path"]))
        case "Bash", "BashOutput", "KillShell", "PowerShell":
            return (.run, TranscriptText.firstString(input, ["command"]))
        case "Grep", "Glob", "ToolSearch", "LSP":
            return (.search, TranscriptText.firstString(input, ["pattern", "query"]))
        case "WebFetch", "WebSearch":
            return (.fetch, TranscriptText.firstString(input, ["url", "query"]))
        case "TodoWrite", "TaskCreate", "TaskUpdate", "EnterPlanMode":
            return (.plan, nil)
        case "Task", "Agent":
            return (.delegate, TranscriptText.firstString(input, ["description"]))
        case "AskUserQuestion":
            let questions = input["questions"] as? [[String: Any]] ?? []
            return (.question, questions.compactMap { TranscriptText.string($0["question"]) }.first)
        case "ExitPlanMode":
            return (.question, "Plan ready for your review")
        default:
            return (.other, nil)
        }
    }
}
