import Foundation

// Rollout format ported from agentsview (MIT, github.com/kenn-io/agentsview), internal/parser/codex.go.
public enum CodexTranscript {
    public static func events(from line: Data) -> [TranscriptEvent] {
        guard let entry = TranscriptText.json(line), let payload = entry["payload"] as? [String: Any] else { return [] }
        switch entry["type"] as? String {
        case "turn_context": return TranscriptText.string(payload["model"]).map { [.model($0)] } ?? []
        case "event_msg": return eventMessage(payload)
        case "response_item": return responseItem(payload)
        case "compacted": return [.compacted]
        default: return []
        }
    }

    public static func sessionCWD(from line: Data) -> String? {
        guard let entry = TranscriptText.json(line), entry["type"] as? String == "session_meta",
              let payload = entry["payload"] as? [String: Any] else { return nil }
        return TranscriptText.string(payload["cwd"])
    }

    private static func eventMessage(_ payload: [String: Any]) -> [TranscriptEvent] {
        switch payload["type"] as? String {
        case "user_message":
            return [.userPrompt(userRequest(payload["message"] as? String ?? ""))]
        case "task_started":
            return [.turnStarted]
        case "task_complete":
            return [.turnEnded]
        case "turn_aborted":
            return [.interrupted]
        case "error":
            let message = TranscriptText.string(payload["message"]) ?? "Codex error"
            return [payload["codex_error_info"] as? String == "usage_limit_exceeded" ? .limitReached(message) : .failed(message)]
        case "context_compacted":
            return [.compacted]
        case "thread_name_updated":
            return TranscriptText.string(payload["thread_name"]).map { [.title($0, generated: false)] } ?? []
        case "token_count":
            guard let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any],
                  let used = last["input_tokens"] as? Int, used > 0 else { return [] }
            return [.contextUsage(usedTokens: used, windowTokens: info["model_context_window"] as? Int)]
        default:
            return []
        }
    }

    private static func userRequest(_ message: String) -> String {
        let marker = "## My request for Codex:"
        guard let range = message.range(of: marker, options: .backwards) else { return message }
        return String(message[range.upperBound...])
    }

    private static func responseItem(_ payload: [String: Any]) -> [TranscriptEvent] {
        switch payload["type"] as? String {
        case "message":
            guard payload["role"] as? String == "assistant" else { return [] }
            let blocks = payload["content"] as? [[String: Any]] ?? []
            return [.assistantText(blocks.compactMap { $0["text"] as? String }.joined(separator: " "))]
        case "reasoning":
            return [.thinking]
        case "function_call", "custom_tool_call":
            guard let id = TranscriptText.string(payload["call_id"]), let name = TranscriptText.string(payload["name"]) else { return [] }
            let input = TranscriptText.jsonObject(string: payload["arguments"] as? String) ?? [:]
            let (kind, subject) = classify(name, input)
            return [.toolCall(ToolCall(id: id, name: name, kind: kind, subject: subject,
                            questions: kind == .question ? TranscriptText.questions(input) : []))]
        case "function_call_output", "custom_tool_call_output":
            return TranscriptText.string(payload["call_id"]).map { [.toolResult(id: $0)] } ?? []
        default:
            return []
        }
    }

    static func classify(_ name: String, _ input: [String: Any]) -> (ToolCall.Kind, String?) {
        switch name {
        case "exec_command", "shell", "shell_command", "exec", "write_stdin", "js":
            return (.run, TranscriptText.firstString(input, ["cmd", "command"]))
        case "apply_patch":
            return (.edit, nil)
        case "view_image":
            return (.read, TranscriptText.firstString(input, ["path"]))
        case "update_plan", "create_goal":
            return (.plan, nil)
        case "spawn_agent", "wait", "wait_agent", "send_message", "close_agent":
            return (.delegate, nil)
        case "request_user_input":
            let questions = input["questions"] as? [[String: Any]] ?? []
            return (.question, questions.compactMap { TranscriptText.string($0["question"]) }.first)
        default:
            return (.other, nil)
        }
    }
}
