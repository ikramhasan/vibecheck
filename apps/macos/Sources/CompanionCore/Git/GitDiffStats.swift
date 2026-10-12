import Foundation

public protocol DiffStatsComputing: Sendable {
    func baseline(in checkout: String, at date: Date?) async -> String?
    func stats(in checkout: String, since baseline: String) async -> DiffStats?
}

public struct GitDiffStats: DiffStatsComputing {
    public static let timeout: TimeInterval = 5
    static let largestCountedFile = 16 * 1024 * 1024

    public let executable: URL

    public init(executable: URL) { self.executable = executable }

    public static func locate(fileManager: FileManager = .default) -> GitDiffStats? {
        let installed = ["/opt/homebrew/bin/git", "/usr/local/bin/git"].first { fileManager.isExecutableFile(atPath: $0) }
        if let installed { return GitDiffStats(executable: URL(fileURLWithPath: installed)) }
        let developer = (try? fileManager.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
            ?? "/Library/Developer/CommandLineTools"
        guard fileManager.isExecutableFile(atPath: developer + "/usr/bin/git") else { return nil }
        return GitDiffStats(executable: URL(fileURLWithPath: "/usr/bin/git"))
    }

    public func baseline(in checkout: String, at date: Date?) async -> String? {
        guard let date else { return await commit(in: checkout, ["rev-parse", "-q", "--verify", "HEAD^{commit}"]) }
        let seconds = Int(date.timeIntervalSince1970)
        if let fromReflog = await commit(in: checkout, ["rev-parse", "-q", "--verify", "HEAD@{@\(seconds)}^{commit}"]) {
            return fromReflog
        }
        return await commit(in: checkout, ["rev-list", "-1", "--before=\(seconds)", "HEAD"])
    }

    public func stats(in checkout: String, since baseline: String) async -> DiffStats? {
        guard let tracked = await git(in: checkout, ["diff", "--numstat", "-z", baseline, "--"]), tracked.status == 0,
              let untracked = await git(in: checkout, ["ls-files", "--others", "--exclude-standard", "-z"]),
              untracked.status == 0,
              let ancestry = await git(in: checkout, ["merge-base", "--is-ancestor", baseline, "HEAD"]) else { return nil }
        var stats = DiffStats.numstat(tracked.stdout)
        for path in untracked.stdout.split(separator: 0) where path.last != UInt8(ascii: "/") {
            let url = URL(fileURLWithPath: checkout).appending(path: String(decoding: path, as: UTF8.self))
            stats.add(lines: Self.newFileLines(url).map { ($0, 0) })
        }
        stats.baselineLeftHistory = ancestry.status == 1
        return stats
    }

    private static func newFileLines(_ url: URL) -> Int? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= largestCountedFile,
              let contents = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return DiffStats.lineCount(of: contents)
    }

    private func commit(in checkout: String, _ arguments: [String]) async -> String? {
        guard let output = await git(in: checkout, arguments), output.status == 0 else { return nil }
        let sha = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    private func git(in checkout: String, _ arguments: [String]) async -> ProcessRunner.Output? {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        let arguments = ["-C", checkout, "-c", "core.quotepath=off", "--no-pager"] + arguments
        return try? await ProcessRunner.run(executable, arguments, environment: environment, timeout: Self.timeout)
    }
}
