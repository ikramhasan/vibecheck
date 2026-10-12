import Foundation
import Testing
@testable import CompanionCore

@Suite struct DiffStatsParsingTests {
    @Test func sumsNumstatAndCountsBinaryAndRenamedFiles() {
        let output = "12\t3\tsrc/a.swift\0-\t-\tlogo.png\0" + "4\t4\t\0old.swift\0new.swift\0"
        let stats = DiffStats.numstat(Data(output.utf8))
        #expect(stats == DiffStats(files: 3, added: 16, removed: 7, binaryFiles: 1))
    }

    @Test func emptyNumstatIsEmpty() {
        #expect(DiffStats.numstat(Data()).isEmpty)
    }

    @Test func countsNewFileLinesLikeGit() {
        #expect(DiffStats.lineCount(of: Data("a\nb\n".utf8)) == 2)
        #expect(DiffStats.lineCount(of: Data("a\nb".utf8)) == 2)
        #expect(DiffStats.lineCount(of: Data()) == 0)
        #expect(DiffStats.lineCount(of: Data([0x61, 0x00, 0x62])) == nil)
    }

    @Test func summaryMentionsBinaryFilesBranchChangesAndSharedCheckouts() {
        let stats = DiffStats(files: 2, added: 5, removed: 1, binaryFiles: 1, baselineLeftHistory: true)
        #expect(DiffSummary.lines(stats, sharedWith: 1) == [
            "2 files changed since this session started (+5 −1)",
            "1 binary file",
            "The branch changed since this session started. Reset to count from here.",
            "Includes changes from 1 other session in this checkout",
        ])
        #expect(DiffSummary.count(1240) == "1.2k")
    }

    @Test func splitsAGitDiffIntoOnePatchPerFile() {
        let diff = "diff --git a/a.txt b/a.txt\n@@ -1 +1 @@\n-a\n+b\ndiff --git a/c.txt b/c.txt\n@@ -1 +1 @@\n-c\n+d\n"
        #expect(GitDiffStats.split(diff) == [
            "diff --git a/a.txt b/a.txt\n@@ -1 +1 @@\n-a\n+b\n",
            "diff --git a/c.txt b/c.txt\n@@ -1 +1 @@\n-c\n+d\n",
        ])
        #expect(GitDiffStats.split("").isEmpty)
    }

    @Test func buildsAPatchForANewFile() {
        let header = "diff --git a/n.txt b/n.txt\nnew file mode 100644\n"
        #expect(GitDiffStats.newFilePatch(path: "n.txt", contents: Data("a\nb\n".utf8))
            == header + "--- /dev/null\n+++ b/n.txt\n@@ -0,0 +1,2 @@\n+a\n+b\n")
        #expect(GitDiffStats.newFilePatch(path: "n.txt", contents: Data("a".utf8))
            == header + "--- /dev/null\n+++ b/n.txt\n@@ -0,0 +1,1 @@\n+a\n\\ No newline at end of file\n")
        #expect(GitDiffStats.newFilePatch(path: "n.txt", contents: Data([0, 1]))
            == header + "Binary files /dev/null and b/n.txt differ\n")
    }

    @Test func ignoresChangesInsideTheGitDirectory() {
        #expect(CheckoutWatcher.isInsideGitDirectory("/repo/.git/index"))
        #expect(CheckoutWatcher.isInsideGitDirectory("/repo/.git"))
        #expect(!CheckoutWatcher.isInsideGitDirectory("/repo/src/.gitignore"))
    }
}

@Suite(.serialized) struct GitDiffStatsTests {
    private let git = GitDiffStats.locate()

    private func repo() throws -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: "vibecheck-diff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let path = url.resolvingSymlinksInPath().path
        try run(path, "init", "-q", "-b", "main")
        try write(path, "a.txt", "one\ntwo\nthree\n")
        try commit(path, "first")
        return path
    }

    private func write(_ repo: String, _ name: String, _ contents: String) throws {
        try contents.write(toFile: repo + "/" + name, atomically: true, encoding: .utf8)
    }

    private func commit(_ repo: String, _ message: String) throws {
        try run(repo, "add", "-A")
        try run(repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", message)
    }

    @discardableResult
    private func run(_ repo: String, _ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = try #require(git).executable
        process.arguments = ["-C", repo] + arguments
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        process.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func countsUncommittedCommittedAndNewFilesAgainstTheBaseline() async throws {
        let git = try #require(git)
        let repo = try repo()
        let baseline = try #require(await git.baseline(in: repo, at: nil))

        try write(repo, "a.txt", "one\n2\nthree\nfour\n")
        try commit(repo, "agent work")
        try write(repo, "b.txt", "new\nfile\n")
        try write(repo, "c.txt", "x\n")
        try run(repo, "add", "c.txt")
        try Data([0, 1, 2]).write(to: URL(fileURLWithPath: repo + "/blob.bin"))

        let stats = try #require(await git.stats(in: repo, since: baseline))
        #expect(stats == DiffStats(files: 4, added: 5, removed: 1, binaryFiles: 1))
        #expect(!FileManager.default.fileExists(atPath: repo + "/.git/index.lock"))
    }

    @Test func baselineIsTheCommitHeadPointedAtWhenTheSessionStarted() async throws {
        let git = try #require(git)
        let repo = try repo()
        let first = try run(repo, "rev-parse", "HEAD")
        let startedAt = Date.now
        try await Task.sleep(for: .seconds(1.1))
        try write(repo, "a.txt", "changed\n")
        try commit(repo, "later")

        #expect(await git.baseline(in: repo, at: startedAt) == first)
        #expect(await git.baseline(in: repo, at: nil) == (try run(repo, "rev-parse", "HEAD")))
    }

    @Test func patchesCoverTrackedAndNewFiles() async throws {
        let git = try #require(git)
        let repo = try repo()
        let baseline = try #require(await git.baseline(in: repo, at: nil))
        try write(repo, "a.txt", "one\n2\nthree\n")
        try write(repo, "new.txt", "hello\n")

        let patches = try #require(await git.patches(in: repo, since: baseline))
        #expect(patches.count == 2)
        #expect(patches[0].patch.hasPrefix("diff --git a/a.txt b/a.txt\n") && patches[0].patch.contains("\n-two\n+2\n"))
        #expect(patches[1] == FilePatch(patch: GitDiffStats.newFilePatch(path: "new.txt", contents: Data("hello\n".utf8)),
                                        untracked: true))
    }

    @Test func flagsABaselineThatLeftHistory() async throws {
        let git = try #require(git)
        let repo = try repo()
        try run(repo, "checkout", "-q", "-b", "feature")
        try write(repo, "a.txt", "feature\n")
        try commit(repo, "feature work")
        let baseline = try #require(await git.baseline(in: repo, at: nil))
        try run(repo, "checkout", "-q", "main")

        #expect(try #require(await git.stats(in: repo, since: baseline)).baselineLeftHistory)
    }
}

private actor FakeDiffs: DiffStatsComputing {
    var statsCalls = 0
    var head = "head-1"
    var baselineDates: [Date?] = []

    func setHead(_ sha: String) { head = sha }

    func baseline(in checkout: String, at date: Date?) async -> String? {
        baselineDates.append(date)
        return date == nil ? head : "start"
    }

    func stats(in checkout: String, since baseline: String) async -> DiffStats? {
        statsCalls += 1
        return DiffStats(files: 1, added: statsCalls, removed: 0, baselineLeftHistory: baseline == "start")
    }

    func patches(in checkout: String, since baseline: String) async -> [FilePatch]? { [] }
}

@MainActor
@Suite(.serialized) struct DiffStatsStoreTests {
    private func session(_ id: String, cwd: String = "/repo", updatedAt: Date = .distantPast) -> AgentSession {
        AgentSession(agent: .init(id: "claude", name: "Claude"), sessionID: id, cwd: cwd, status: .working,
                     startedAt: Date(timeIntervalSince1970: 1000), updatedAt: updatedAt)
    }

    private func store(_ fake: FakeDiffs, defaults: UserDefaults = UserDefaults(suiteName: UUID().uuidString)!) -> DiffStatsStore {
        DiffStatsStore(computer: fake, repository: { $0.hasPrefix("/repo") ? "/repo" : nil },
                       defaults: defaults, watchCheckouts: false)
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(100)) }

    @Test func resolvesTheBaselineFromTheStartTimeAndSkipsNonRepos() async throws {
        let fake = FakeDiffs()
        let store = store(fake)
        let inRepo = session("a"), outside = session("b", cwd: "/tmp/scratch")
        store.update([inRepo, outside])
        try await settle()

        #expect(await fake.baselineDates == [Date(timeIntervalSince1970: 1000)])
        #expect(store.stats(for: inRepo)?.added == 1)
        #expect(store.stats(for: outside) == nil)
    }

    @Test func throttlesRefreshesWhileTheTranscriptKeepsMoving() async throws {
        let fake = FakeDiffs()
        let store = store(fake)
        store.update([session("a")])
        try await settle()
        for step in 1...5 { store.update([session("a", updatedAt: Date(timeIntervalSince1970: Double(step)))]) }
        try await settle()
        #expect(await fake.statsCalls == 1)

        try await Task.sleep(for: .seconds(DiffStatsRefresh.minInterval))
        #expect(await fake.statsCalls == 2)
    }

    @Test func resetCountsFromHeadAndSurvivesARestart() async throws {
        let fake = FakeDiffs()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let s = session("a")
        let first = store(fake, defaults: defaults)
        first.update([s])
        try await settle()
        #expect(first.stats(for: s)?.baselineLeftHistory == true)

        first.resetBaseline(of: s)
        try await Task.sleep(for: .seconds(DiffStatsRefresh.minInterval) + .milliseconds(100))
        #expect(first.stats(for: s)?.baselineLeftHistory == false)

        await fake.setHead("head-2")
        let restarted = store(fake, defaults: defaults)
        restarted.update([s])
        try await settle()
        #expect(restarted.stats(for: s)?.baselineLeftHistory == false)
        #expect(await fake.baselineDates.filter { $0 != nil }.count == 1)
    }

    @Test func countsOtherSessionsInTheSameCheckout() async throws {
        let store = store(FakeDiffs())
        let a = session("a"), b = session("b", cwd: "/repo/sub"), c = session("c", cwd: "/elsewhere")
        store.update([a, b, c])
        #expect(store.sessionsSharingCheckout(with: a) == 1)
        #expect(store.sessionsSharingCheckout(with: c) == 0)
    }
}
