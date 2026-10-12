import Foundation

public protocol DiffStatsComputing: Sendable {
    func baseline(in checkout: String, at date: Date?) async -> String?
    func stats(in checkout: String, since baseline: String) async -> DiffStats?
    func patches(in checkout: String, since baseline: String) async -> [FilePatch]?
    /// The checked-out branch, or `nil` on a detached HEAD.
    func branch(in checkout: String) async -> String?
}

public struct FilePatch: Hashable, Codable, Sendable {
    public var patch: String
    public var untracked: Bool

    public init(patch: String, untracked: Bool = false) {
        self.patch = patch
        self.untracked = untracked
    }
}

public enum GitQuery: Equatable, Sendable {
    case toplevel
    case branch
    case head
    case reflog(at: Int)
    case before(Int)
    case numstat(since: String)
    case untracked
    case isAncestor(String)
    case patch(since: String)

    var arguments: [String] {
        switch self {
        case .toplevel: ["rev-parse", "--show-toplevel"]
        case .branch: ["symbolic-ref", "-q", "--short", "HEAD"]
        case .head: ["rev-parse", "-q", "--verify", "HEAD^{commit}"]
        case .reflog(let seconds): ["rev-parse", "-q", "--verify", "HEAD@{@\(seconds)}^{commit}"]
        case .before(let seconds): ["rev-list", "-1", "--before=\(seconds)", "HEAD"]
        case .numstat(let baseline): ["diff", "--numstat", "-z", baseline, "--"]
        case .untracked: ["ls-files", "--others", "--exclude-standard", "-z"]
        case .isAncestor(let baseline): ["merge-base", "--is-ancestor", baseline, "HEAD"]
        case .patch(let baseline): ["diff", "-M", "--no-color", "--no-ext-diff", "--no-textconv",
                                    "--src-prefix=a/", "--dst-prefix=b/", baseline, "--"]
        }
    }
}

public struct GitOutput: Equatable, Sendable {
    public var status: Int32
    public var stdout: Data

    public init(status: Int32, stdout: Data) {
        self.status = status
        self.stdout = stdout
    }
}

/// Where git runs: this Mac, or another machine over its ssh connection.
public protocol GitReading: Sendable {
    func run(_ query: GitQuery, in checkout: String) async -> GitOutput?
    /// An untracked file's contents, or `nil` if it's missing or over `GitDiffStats.largestCountedFile`.
    func contents(of path: String, in checkout: String) async -> Data?
}

public struct LocalGit: GitReading {
    public static let timeout: TimeInterval = 5

    public let executable: URL

    public init(executable: URL) { self.executable = executable }

    public func run(_ query: GitQuery, in checkout: String) async -> GitOutput? {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        let arguments = ["-C", checkout, "-c", "core.quotepath=off", "--no-pager"] + query.arguments
        guard let output = try? await ProcessRunner.run(executable, arguments, environment: environment,
                                                         timeout: Self.timeout) else { return nil }
        return GitOutput(status: output.status, stdout: output.stdout)
    }

    public func contents(of path: String, in checkout: String) async -> Data? {
        let url = URL(fileURLWithPath: checkout).appending(path: path)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= GitDiffStats.largestCountedFile else { return nil }
        return try? Data(contentsOf: url, options: .alwaysMapped)
    }
}

public struct GitDiffStats: DiffStatsComputing {
    public static let largestCountedFile = 16 * 1024 * 1024

    public let git: GitReading

    public init(git: GitReading) { self.git = git }

    public static func locate(fileManager: FileManager = .default) -> GitDiffStats? {
        let installed = ["/opt/homebrew/bin/git", "/usr/local/bin/git"].first { fileManager.isExecutableFile(atPath: $0) }
        if let installed { return GitDiffStats(git: LocalGit(executable: URL(fileURLWithPath: installed))) }
        let developer = (try? fileManager.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
            ?? "/Library/Developer/CommandLineTools"
        guard fileManager.isExecutableFile(atPath: developer + "/usr/bin/git") else { return nil }
        return GitDiffStats(git: LocalGit(executable: URL(fileURLWithPath: "/usr/bin/git")))
    }

    public func baseline(in checkout: String, at date: Date?) async -> String? {
        guard let date else { return await commit(in: checkout, .head) }
        let seconds = Int(date.timeIntervalSince1970)
        if let fromReflog = await commit(in: checkout, .reflog(at: seconds)) { return fromReflog }
        return await commit(in: checkout, .before(seconds))
    }

    public func stats(in checkout: String, since baseline: String) async -> DiffStats? {
        guard let tracked = await git.run(.numstat(since: baseline), in: checkout), tracked.status == 0,
              let untracked = await git.run(.untracked, in: checkout), untracked.status == 0,
              let ancestry = await git.run(.isAncestor(baseline), in: checkout) else { return nil }
        var stats = DiffStats.numstat(tracked.stdout)
        for path in untracked.stdout.split(separator: 0) where path.last != UInt8(ascii: "/") {
            let contents = await git.contents(of: String(decoding: path, as: UTF8.self), in: checkout)
            stats.add(lines: contents.flatMap(DiffStats.lineCount(of:)).map { ($0, 0) })
        }
        stats.baselineLeftHistory = ancestry.status == 1
        return stats
    }

    public func patches(in checkout: String, since baseline: String) async -> [FilePatch]? {
        guard let tracked = await git.run(.patch(since: baseline), in: checkout), tracked.status == 0,
              let untracked = await git.run(.untracked, in: checkout), untracked.status == 0 else { return nil }
        var patches = Self.split(String(decoding: tracked.stdout, as: UTF8.self)).map { FilePatch(patch: $0) }
        for path in untracked.stdout.split(separator: 0) where path.last != UInt8(ascii: "/") {
            let path = String(decoding: path, as: UTF8.self)
            let contents = await git.contents(of: path, in: checkout)
            patches.append(FilePatch(patch: Self.newFilePatch(path: path, contents: contents), untracked: true))
        }
        return patches
    }

    public func branch(in checkout: String) async -> String? {
        await commit(in: checkout, .branch)
    }

    static func split(_ diff: String) -> [String] {
        var files: [String] = []
        var current = ""
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git "), !current.isEmpty {
                files.append(current)
                current = ""
            }
            current += line
            current += "\n"
        }
        if current.contains("diff --git ") { files.append(String(current.dropLast())) }
        return files
    }

    static func newFilePatch(path: String, contents: Data?) -> String {
        let header = "diff --git a/\(path) b/\(path)\nnew file mode 100644\n"
        guard let contents, DiffStats.lineCount(of: contents) != nil else {
            return header + "Binary files /dev/null and b/\(path) differ\n"
        }
        let text = String(decoding: contents, as: UTF8.self)
        guard !text.isEmpty else { return header }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let endsWithNewline = lines.last == ""
        if endsWithNewline { lines.removeLast() }
        var patch = header + "--- /dev/null\n+++ b/\(path)\n@@ -0,0 +1,\(lines.count) @@\n"
        for line in lines { patch += "+" + line + "\n" }
        if !endsWithNewline { patch += "\\ No newline at end of file\n" }
        return patch
    }

    private func commit(in checkout: String, _ query: GitQuery) async -> String? {
        guard let output = await git.run(query, in: checkout), output.status == 0 else { return nil }
        let line = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }
}
