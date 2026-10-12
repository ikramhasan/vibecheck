import Foundation

public protocol DiffStatsComputing: Sendable {
    func baseline(in checkout: String, at date: Date?) async -> String?
    func stats(in checkout: String, since baseline: String) async -> DiffStats?
    func patches(in checkout: String, since baseline: String) async -> [FilePatch]?
}

public struct FilePatch: Hashable, Codable, Sendable {
    public var patch: String
    public var untracked: Bool

    public init(patch: String, untracked: Bool = false) {
        self.patch = patch
        self.untracked = untracked
    }
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

    public func patches(in checkout: String, since baseline: String) async -> [FilePatch]? {
        guard let tracked = await git(in: checkout, ["diff", "-M", "--no-color", "--no-ext-diff", "--no-textconv",
                                                     "--src-prefix=a/", "--dst-prefix=b/", baseline, "--"]),
              tracked.status == 0,
              let untracked = await git(in: checkout, ["ls-files", "--others", "--exclude-standard", "-z"]),
              untracked.status == 0 else { return nil }
        var patches = Self.split(String(decoding: tracked.stdout, as: UTF8.self)).map { FilePatch(patch: $0) }
        for path in untracked.stdout.split(separator: 0) where path.last != UInt8(ascii: "/") {
            let path = String(decoding: path, as: UTF8.self)
            let url = URL(fileURLWithPath: checkout).appending(path: path)
            patches.append(FilePatch(patch: Self.newFilePatch(path: path, contents: Self.countableContents(url)),
                                     untracked: true))
        }
        return patches
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

    private static func countableContents(_ url: URL) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= largestCountedFile else { return nil }
        return try? Data(contentsOf: url, options: .alwaysMapped)
    }

    private static func newFileLines(_ url: URL) -> Int? {
        countableContents(url).flatMap(DiffStats.lineCount(of:))
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
