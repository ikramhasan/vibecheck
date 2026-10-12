import Darwin
import Foundation

public enum ActionProcess {
    static let killDelay: Duration = .seconds(3)

    public enum LaunchError: Error, Equatable {
        case spawnFailed(Int32)
    }

    public static func launch(command: String, directory: String, shell: String,
                              environment: [String: String], log: URL) throws -> Int32 {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
                                                    | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attributes, 0)
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)

        var files: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&files)
        defer { posix_spawn_file_actions_destroy(&files) }
        posix_spawn_file_actions_addopen(&files, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&files, STDOUT_FILENO, log.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_adddup2(&files, STDOUT_FILENO, STDERR_FILENO)
        posix_spawn_file_actions_addchdir_np(&files, directory)

        let arguments: [UnsafeMutablePointer<CChar>?] = [shell, "-c", command].map { strdup($0) } + [nil]
        let variables: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (arguments + variables).forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, shell, &files, &attributes, arguments, variables)
        guard result == 0 else { throw LaunchError.spawnFailed(result) }
        return pid
    }

    public static func waitForExit(_ pid: Int32) -> ActionRun.Outcome {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            guard errno == EINTR else { return .failed("Lost track of the process") }
        }
        let signal = status & 0x7f
        return signal == 0 ? .exited((status >> 8) & 0xff) : .signaled(signal)
    }

    public static func stop(_ pid: Int32, isRunning: @Sendable () async -> Bool) async {
        let tree = tree(of: pid, in: ProcessScanner.userProcesses())
        kill(-pid, SIGTERM)
        for process in tree { kill(process.pid, SIGTERM) }
        let deadline = ContinuousClock.now + killDelay
        while ContinuousClock.now < deadline {
            if await !isRunning(), tree.allSatisfy({ !isAlive($0) }) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let survivors = tree.filter(isAlive)
        if await isRunning() || !survivors.isEmpty { kill(-pid, SIGKILL) }
        for process in survivors { kill(process.pid, SIGKILL) }
    }

    static func tree(of pid: Int32, in processes: [ProcessEntry]) -> [ProcessEntry] {
        let children = Dictionary(grouping: processes, by: \.parentPID)
        var tree = processes.filter { $0.pid == pid }
        var index = 0
        while index < tree.count {
            tree += children[tree[index].pid, default: []].filter { child in !tree.contains { $0.pid == child.pid } }
            index += 1
        }
        return tree
    }

    private static func isAlive(_ process: ProcessEntry) -> Bool {
        ProcessScanner.entry(pid: process.pid)?.startedAt == process.startedAt
    }
}

public enum ActionLog {
    public static let maxLines = 5_000
    static let maxBytes = 1_000_000

    public static func read(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return clean(String(decoding: data, as: UTF8.self), truncated: start > 0)
    }

    static func clean(_ text: String, truncated: Bool = false) -> String {
        let plain = text.replacing(/\u{1B}\[[0-9;?]*[ -\/]*[@-~]|\u{1B}\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\)/, with: "")
        var lines = plain.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.split(separator: "\r", omittingEmptySubsequences: false).last(where: { !$0.isEmpty }) ?? ""
        }
        if truncated, !lines.isEmpty { lines.removeFirst() }
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines.suffix(maxLines).joined(separator: "\n")
    }
}
