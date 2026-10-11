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
        #expect(t.title == "Login redirect fix")
        #expect(t.model == "claude-opus-5-5")
        #expect(t.context == .init(usedTokens: 150_510, windowTokens: 200_000))
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
        #expect(t.attention == .init(kind: .question, message: "Which database should we use?"))
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

    @Test func largeContextSwitchesToMillionTokenWindow() {
        var t = SessionTimeline()
        t.apply(.contextUsage(usedTokens: 250_000, windowTokens: nil))
        #expect(t.context?.windowTokens == 1_000_000)
    }
}

@Suite struct CodexTranscriptTests {
    @Test func taskCompleteIsYourTurn() throws {
        let t = try timeline("codex/turn-complete.jsonl", .codex)
        #expect(t.status == .idle)
        #expect(t.task == "Add Stripe checkout")
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

@Suite struct ClaudeNotificationTests {
    @Test func backgroundTaskNotificationWorksWithoutReplacingTask() throws {
        let t = try timeline("claude/background-task.jsonl", .claude)
        #expect(t.status == .working)
        #expect(t.task == "Run the tests")
    }
}
