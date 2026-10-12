import Darwin
import Foundation
import Testing
@testable import CompanionCore

@MainActor
@Suite struct ActionStoreTests {
    let folder: URL
    let defaults: UserDefaults
    let store: ActionStore

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "vibecheck-actions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "vibecheck-tests-\(UUID().uuidString)")!
        store = ActionStore(defaults: defaults, logDirectory: folder.appending(path: "logs"), shell: "/bin/sh",
                            environment: { ["PATH": "/usr/bin:/bin", "GREETING": "hello"] })
    }

    private func action(_ command: String, directory: String? = nil) -> QuickAction {
        QuickAction(name: "Test", command: command, directory: directory ?? folder.path)
    }

    private func waitUntilFinished(_ action: QuickAction, timeout: Duration = .seconds(10)) async -> ActionRun? {
        let deadline = ContinuousClock.now + timeout
        while store.run(for: action)?.isRunning == true, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return store.run(for: action)
    }

    @Test func savedActionsPersist() {
        let saved = action("echo hi")
        store.save(saved)
        var renamed = saved
        renamed.name = "Renamed"
        store.save(renamed)
        let reloaded = ActionStore(defaults: defaults, logDirectory: folder, shell: "/bin/sh", environment: { [:] })
        #expect(reloaded.actions == [renamed])
    }

    @Test func reportsTheExitCodeAndCapturesOutput() async {
        let failing = action("echo \"$GREETING from $(basename \"$(pwd)\")\"; echo oops >&2; exit 3")
        store.save(failing)
        store.run(failing)
        guard case .finished(let outcome, _) = await waitUntilFinished(failing) else {
            Issue.record("still running")
            return
        }
        #expect(outcome == .exited(3))
        #expect(store.log(for: failing) == "hello from \(folder.lastPathComponent)\noops")
    }

    @Test func aMissingFolderFailsWithoutRunning() {
        let missing = action("true", directory: folder.appending(path: "gone").path)
        store.save(missing)
        store.run(missing)
        #expect(store.run(for: missing) == .finished(.failed("Folder not found"), endedAt: store.run(for: missing)!.endedAt))
    }

    @Test func stopTerminatesTheWholeTree() async throws {
        let pidFile = folder.appending(path: "child.pid")
        let tree = action("sleep 60 & echo $! > '\(pidFile.path)'; wait")
        store.save(tree)
        store.run(tree)
        let deadline = ContinuousClock.now + .seconds(10)
        while (try? String(contentsOf: pidFile, encoding: .utf8))?.isEmpty ?? true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let child = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(child, 0) == 0)

        store.stop(tree)
        guard case .finished(let outcome, _) = await waitUntilFinished(tree) else {
            Issue.record("still running")
            return
        }
        #expect(outcome == .stopped)
        let gone = ContinuousClock.now + .seconds(5)
        while ProcessScanner.entry(pid: child) != nil, ContinuousClock.now < gone {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(ProcessScanner.entry(pid: child) == nil)
    }

    @Test func runsInEachFolderAreTrackedSeparately() async throws {
        let other = folder.appending(path: "worktree")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let saved = action("basename \"$(pwd)\"")
        store.save(saved)
        store.run(saved)
        store.run(saved, in: other.path)
        let deadline = ContinuousClock.now + .seconds(10)
        while store.running.count > 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.log(for: saved) == folder.lastPathComponent)
        #expect(store.log(for: saved, in: other.path) == "worktree")
        #expect(store.otherDirectories(of: saved) == [other.path])

        store.dismiss(saved, in: other.path)
        #expect(store.otherDirectories(of: saved).isEmpty)
        #expect(store.run(for: saved, in: other.path) == nil)
        #expect(!FileManager.default.fileExists(atPath: store.logURL(for: saved, in: other.path).path))
        #expect(store.run(for: saved) != nil)
    }

    @Test func deletingAnActionRemovesItsLog() async {
        let saved = action("echo hi")
        store.save(saved)
        store.run(saved)
        _ = await waitUntilFinished(saved)
        #expect(FileManager.default.fileExists(atPath: store.logURL(for: saved).path))
        store.delete(saved)
        #expect(store.actions.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.logURL(for: saved).path))
    }
}

private extension ActionRun {
    var endedAt: Date {
        if case .finished(_, let date) = self { return date }
        return .distantPast
    }
}

@Suite struct ActionLogTests {
    @Test func stripsColorsAndCarriageReturnProgress() {
        let raw = "\u{1B}[32mready\u{1B}[0m in 120ms\n10%\r50%\r100%\n\u{1B}]8;;http://x\u{07}link\u{1B}]8;;\u{07}\n"
        #expect(ActionLog.clean(raw) == "ready in 120ms\n100%\nlink")
    }

    @Test func dropsThePartialFirstLineOfATruncatedRead() {
        #expect(ActionLog.clean("tail of a line\nwhole line\n", truncated: true) == "whole line")
    }

    @Test func keepsOnlyTheLastLines() {
        let lines = (1...(ActionLog.maxLines + 10)).map(String.init).joined(separator: "\n")
        let cleaned = ActionLog.clean(lines).split(separator: "\n")
        #expect(cleaned.count == ActionLog.maxLines)
        #expect(cleaned.last == "\(ActionLog.maxLines + 10)")
    }
}

@Suite struct ShellEnvironmentTests {
    @Test func readsVariablesAfterTheMarkerAndDropsShellState() {
        let output = "Welcome!\n\(ShellEnvironment.marker)PATH=/opt/homebrew/bin:/usr/bin\0EQ=a=b\0PWD=/tmp\0SHLVL=2\0"
        #expect(ShellEnvironment.parse(Data(output.utf8)) == ["PATH": "/opt/homebrew/bin:/usr/bin", "EQ": "a=b"])
    }

    @Test func noMarkerMeansNoEnvironment() {
        #expect(ShellEnvironment.parse(Data("zsh: command not found".utf8)) == nil)
    }
}

@Suite struct ProcessTreeTests {
    @Test func collectsDescendantsOnly() {
        let processes = [
            ProcessEntry(pid: 10, parentPID: 1, name: "sh"),
            ProcessEntry(pid: 11, parentPID: 10, name: "node"),
            ProcessEntry(pid: 12, parentPID: 11, name: "esbuild"),
            ProcessEntry(pid: 20, parentPID: 1, name: "other"),
        ]
        #expect(ActionProcess.tree(of: 10, in: processes).map(\.pid) == [10, 11, 12])
    }
}
