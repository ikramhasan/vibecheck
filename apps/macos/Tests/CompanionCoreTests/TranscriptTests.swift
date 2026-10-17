import Foundation
import Testing
@testable import CompanionCore

private func fixture(_ path: String) throws -> URL {
    try #require(Bundle.module.url(forResource: "Fixtures/\(path)", withExtension: nil))
}

private func timeline(_ path: String, _ format: TranscriptFormat) throws -> SessionTimeline {
    var file = TranscriptFile(url: try fixture(path))
    guard case .restarted(let lines) = file.readNewLines() else { throw CancellationError() }
    var timeline = SessionTimeline()
    timeline.apply(lines.flatMap(format.events(from:)))
    return timeline
}

@Suite struct ClaudeTranscriptTests {
    @Test func endTurnIsYourTurn() throws {
        let t = try timeline("claude/turn-ended.jsonl", .claude)
        #expect(t.status == .idle)
        #expect(!t.wasInterrupted)
        #expect(t.task == "Fix the login redirect")
        #expect(t.lastReply == "Fixed it.")
        #expect(t.title == "Login redirect fix")
        #expect(t.model == "claude-opus-5-5")
        #expect(t.context == .init(usedTokens: 150_510, windowTokens: 1_000_000))
        #expect(t.activity == nil)
    }

    @Test func pendingToolIsWorkingWithActivity() throws {
        let t = try timeline("claude/running-tool.jsonl", .claude)
        #expect(t.status == .working)
        #expect(t.activity == "Running npm test")
    }

    @Test func questionToolNeedsAttention() throws {
        let t = try timeline("claude/asking.jsonl", .claude)
        #expect(t.status == .needsAttention)
        #expect(t.attention == .init(kind: .question, message: "Which database should we use?", questions: [
            .init(header: "DB", question: "Which database should we use?", options: [
                .init(label: "Postgres (Recommended)", description: "Relational, matches the existing schema."),
                .init(label: "SQLite", description: "Single file, no server."),
            ]),
        ]))
    }

    @Test func interruptGoesIdleWithoutFinishing() throws {
        let t = try timeline("claude/interrupted.jsonl", .claude)
        #expect(t.status == .idle)
        #expect(t.wasInterrupted)
    }

    @Test func rateLimitBlocks() throws {
        let t = try timeline("claude/rate-limit.jsonl", .claude)
        #expect(t.status == .blocked)
        #expect(t.activity == "You've hit your session limit · resets 3:47pm")
    }

    @Test func slashCommandBecomesTask() throws {
        let t = try timeline("claude/slash-command.jsonl", .claude)
        #expect(t.task == "/compact")
        #expect(t.activity == "Compacting…")
    }

    @Test func currentModelsHaveMillionTokenWindow() {
        #expect(SessionTimeline.claudeWindow(model: "claude-opus-5-5", usedTokens: 50_000) == 1_000_000)
        #expect(SessionTimeline.claudeWindow(model: "claude-haiku-5-5", usedTokens: 50_000) == 1_000_000)
        #expect(SessionTimeline.claudeWindow(model: nil, usedTokens: 50_000) == 1_000_000)
    }

    @Test func legacyModelsHaveTwoHundredThousandTokenWindow() {
        #expect(SessionTimeline.claudeWindow(model: "claude-haiku-4-5-20251001", usedTokens: 50_000) == 200_000)
        #expect(SessionTimeline.claudeWindow(model: "claude-sonnet-4-20250514", usedTokens: 50_000) == 200_000)
        #expect(SessionTimeline.claudeWindow(model: "claude-3-7-sonnet-20250219", usedTokens: 50_000) == 200_000)
    }

    @Test func legacyModelOverTwoHundredThousandTokensUsesMillionTokenWindow() {
        #expect(SessionTimeline.claudeWindow(model: "claude-sonnet-4-5", usedTokens: 250_000) == 1_000_000)
    }
}

@Suite struct CodexTranscriptTests {
    @Test func taskCompleteIsYourTurn() throws {
        let t = try timeline("codex/turn-complete.jsonl", .codex)
        #expect(t.status == .idle)
        #expect(t.task == "Add Stripe checkout")
        #expect(t.lastReply == "Done.")
        #expect(t.title == "Stripe checkout")
        #expect(t.model == "gpt-5.5-codex")
        #expect(t.context == .init(usedTokens: 64_600, windowTokens: 258_400))
    }

    @Test func pendingCallIsWorking() throws {
        let t = try timeline("codex/running-tool.jsonl", .codex)
        #expect(t.status == .working)
        #expect(t.activity == "Running swift build")
    }

    @Test func requestUserInputNeedsAttention() throws {
        let t = try timeline("codex/question.jsonl", .codex)
        #expect(t.status == .needsAttention)
        #expect(t.attention?.message == "How should v1 execute Python?")
        #expect(t.attention?.questions == [.init(header: "Python Run", question: "How should v1 execute Python?", options: [
            .init(label: "Browser-only", description: "Pyodide in the browser."), .init(label: "Server-backed"),
        ])])
    }

    @Test func abortedTurnIsInterrupted() throws {
        let t = try timeline("codex/aborted.jsonl", .codex)
        #expect(t.status == .idle)
        #expect(t.wasInterrupted)
    }

    @Test func usageLimitBlocks() throws {
        let t = try timeline("codex/usage-limit.jsonl", .codex)
        #expect(t.status == .blocked)
    }

    @Test func sessionMetaGivesCWD() throws {
        let line = try Data(contentsOf: try fixture("codex/turn-complete.jsonl")).split(separator: 0x0A).first.map { Data($0) }
        #expect(CodexTranscript.sessionCWD(from: try #require(line)) == "/repo/shop")
    }
}

@Suite struct PiTranscriptTests {
    @Test func stopIsYourTurn() throws {
        let t = try timeline("pi/turn-ended.jsonl", .pi)
        #expect(t.status == .idle)
        #expect(t.task == "Redesign the about section")
        #expect(t.lastReply == "Done")
        #expect(t.title == "About section redesign")
        #expect(t.model == "claude-opus-5")
        #expect(t.context?.usedTokens == 31_200)
        #expect(t.context?.windowTokens == 200_000)
    }

    @Test func pendingToolIsWorking() throws {
        let t = try timeline("pi/running-tool.jsonl", .pi)
        #expect(t.status == .working)
        #expect(t.activity == "Running vercel deploy")
    }

    @Test func abortedErrorIsInterrupt() throws {
        let t = try timeline("pi/aborted.jsonl", .pi)
        #expect(t.status == .idle)
        #expect(t.wasInterrupted)
    }

    @Test func otherErrorFails() throws {
        let t = try timeline("pi/error.jsonl", .pi)
        #expect(t.status == .error)
        #expect(t.activity == "Invalid API key")
    }
}

@Suite struct SessionTimelineTests {
    @Test func toolResultReturnsToThinking() {
        var t = SessionTimeline()
        t.apply([.userPrompt("go"), .toolCall(.init(id: "1", name: "Edit", kind: .edit, subject: "/a/b/auth.ts"))])
        #expect(t.activity == "Editing auth.ts")
        t.apply(.toolResult(id: "1"))
        #expect(t.status == .working)
        #expect(t.activity == "Thinking…")
    }

    @Test func questionWinsOverParallelTool() {
        var t = SessionTimeline()
        t.apply([.userPrompt("go"),
                 .toolCall(.init(id: "1", name: "AskUserQuestion", kind: .question, subject: "Which?")),
                 .toolCall(.init(id: "2", name: "Read", kind: .read, subject: "/x"))])
        #expect(t.status == .needsAttention)
        t.apply(.toolResult(id: "1"))
        #expect(t.status == .working)
        #expect(t.activity == "Reading x")
    }

    @Test func generatedTitleNeverReplacesChosenOne() {
        var t = SessionTimeline()
        t.apply([.title("Chosen", generated: false), .title("Generated", generated: true)])
        #expect(t.title == "Chosen")
    }

    @Test func compactionClearsContext() {
        var t = SessionTimeline()
        t.apply([.contextUsage(usedTokens: 190_000, windowTokens: 200_000), .compacted])
        #expect(t.context == nil)
    }
}

@Suite struct TranscriptFileTests {
    private func tempFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    @Test func holdsBackPartialLineUntilComplete() throws {
        let url = try tempFile("a\nb")
        var file = TranscriptFile(url: url)
        #expect(file.readNewLines() == .restarted([Data("a".utf8)]))
        try append("c\nd\n", to: url)
        #expect(file.readNewLines() == .appended([Data("bc".utf8), Data("d".utf8)]))
        #expect(file.readNewLines() == .appended([]))
    }

    @Test func firstReadStartsAtLineInsideWindow() throws {
        let url = try tempFile("first-line\nsecond\nthird\n")
        var file = TranscriptFile(url: url)
        #expect(file.readNewLines(window: 10) == .restarted([Data("third".utf8)]))
    }

    @Test func shrinkingFileRestarts() throws {
        let url = try tempFile("one\ntwo\n")
        var file = TranscriptFile(url: url)
        _ = file.readNewLines()
        try "new\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(file.readNewLines() == .restarted([Data("new".utf8)]))
    }

    @Test func modificationDateFollowsLaterWrites() throws {
        let url = try tempFile("one\n")
        let file = TranscriptFile(url: url)
        let first = try #require(file.modificationDate)
        let later = first.addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: url.path)
        let modified = try #require(file.modificationDate)
        #expect(abs(modified.timeIntervalSince(later)) < 0.001)
    }
}

@Suite struct SettleScheduleTests {
    @Test func waitsForQuietButNeverLongerThanMax() {
        var schedule = SettleSchedule()
        let start = Date(timeIntervalSince1970: 0)
        #expect(schedule.changed(at: start) == start.addingTimeInterval(SettleDelay.quiet))
        #expect(schedule.changed(at: start.addingTimeInterval(0.2)) == start.addingTimeInterval(0.5))
        #expect(schedule.changed(at: start.addingTimeInterval(0.9)) == start.addingTimeInterval(SettleDelay.maxWait))
        schedule.fired()
        let later = start.addingTimeInterval(5)
        #expect(schedule.changed(at: later) == later.addingTimeInterval(SettleDelay.quiet))
    }
}

@Suite struct ClaudeBackgroundTaskTests {
    private func event(_ json: String) -> [TranscriptEvent] {
        ClaudeTranscript.events(from: Data(json.utf8))
    }

    private func notification(_ id: String, status: String = "completed") -> String {
        #"{"type":"queue-operation","operation":"enqueue","content":"<task-notification>\n<task-id>\#(id)</task-id>\n<status>\#(status)</status>\n</task-notification>"}"#
    }

    @Test func endedTurnKeepsWorkingWhileBackgroundTasksRun() throws {
        let t = try timeline("claude/waiting-on-background.jsonl", .claude)
        #expect(t.status == .working)
        #expect(t.activity == "Waiting on 1 command and 1 monitor")
        #expect(t.lastReply == "I'll wait for the build.")
    }

    @Test func finishedTasksUpdateTheWait() throws {
        var t = try timeline("claude/waiting-on-background.jsonl", .claude)
        t.apply(event(notification("bwatch")))
        #expect(t.activity == "Waiting on 1 command")
        t.apply(event(notification("bbuild", status: "failed")))
        #expect(t.status == .idle)
        t.apply(event(#"{"type":"user","origin":{"kind":"task-notification"},"message":{"role":"user","content":"<task-notification>\n<task-id>bbuild</task-id>\n<status>failed</status>\n</task-notification>"}}"#))
        #expect(t.status == .working)
        #expect(t.activity == "Thinking…")
    }

    @Test func monitorEventsDoNotEndTheTask() throws {
        var t = try timeline("claude/waiting-on-background.jsonl", .claude)
        t.apply(event(#"{"type":"queue-operation","operation":"enqueue","content":"<task-notification>\n<task-id>bwatch</task-id>\n<summary>Monitor event</summary>\n</task-notification>"}"#))
        #expect(t.activity == "Waiting on 1 command and 1 monitor")
    }

    @Test func stoppedTaskEndsTheWait() throws {
        var t = SessionTimeline()
        t.apply(event(#"{"type":"user","toolUseResult":{"backgroundTaskId":"b1"},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#))
        t.apply(event(#"{"type":"user","toolUseResult":{"task_id":"b1","task_type":"local_bash"},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"stopped"}]}}"#))
        t.apply(.turnEnded)
        #expect(t.status == .idle)
    }

    @Test func taskUpdateIsNotABackgroundTask() throws {
        var t = SessionTimeline()
        t.apply(event(#"{"type":"user","toolUseResult":{"success":true,"taskId":"1","updatedFields":["status"]},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"Updated task #1 status"}]}}"#))
        t.apply(.turnEnded)
        #expect(t.status == .idle)
    }

    @Test func asyncAgentCountsAsBackgroundTask() throws {
        var t = SessionTimeline()
        t.apply(event(#"{"type":"user","toolUseResult":{"isAsync":true,"status":"async_launched","agentId":"a1"},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"launched"}]}}"#))
        t.apply(.turnEnded)
        #expect(t.activity == "Waiting on 1 agent")
    }

    @Test func interruptIsIdleEvenWithBackgroundTasks() throws {
        var t = try timeline("claude/waiting-on-background.jsonl", .claude)
        t.apply(.interrupted)
        #expect(t.status == .idle)
        #expect(t.wasInterrupted)
    }
}

@Suite struct ClaudeNotificationTests {
    @Test func backgroundTaskNotificationWorksWithoutReplacingTask() throws {
        let t = try timeline("claude/background-task.jsonl", .claude)
        #expect(t.status == .working)
        #expect(t.task == "Run the tests")
    }

    @Test func stoppedBackgroundTaskEndsTheWaitWithoutANewTurn() throws {
        let t = try timeline("claude/stopped-background-task.jsonl", .claude)
        #expect(t.status == .idle)
        #expect(t.lastReply == "Thanks, cycle 19 is in main.")
    }
}
