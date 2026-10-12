import Foundation

public struct DiffStats: Hashable, Sendable {
    public var files: Int
    public var added: Int
    public var removed: Int
    public var binaryFiles: Int
    public var baselineLeftHistory: Bool

    public init(files: Int = 0, added: Int = 0, removed: Int = 0, binaryFiles: Int = 0,
                baselineLeftHistory: Bool = false) {
        self.files = files
        self.added = added
        self.removed = removed
        self.binaryFiles = binaryFiles
        self.baselineLeftHistory = baselineLeftHistory
    }

    public var isEmpty: Bool { files == 0 && !baselineLeftHistory }

    mutating func add(lines: (added: Int, removed: Int)?) {
        files += 1
        if let lines {
            added += lines.added
            removed += lines.removed
        } else {
            binaryFiles += 1
        }
    }

    static func numstat(_ data: Data) -> DiffStats {
        var stats = DiffStats()
        var fields = data.split(separator: 0, omittingEmptySubsequences: false)[...]
        while let record = fields.popFirst() {
            let columns = record.split(separator: UInt8(ascii: "\t"), maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count == 3 else { continue }
            if columns[2].isEmpty { fields = fields.dropFirst(2) }
            let added = Int(String(decoding: columns[0], as: UTF8.self))
            let removed = Int(String(decoding: columns[1], as: UTF8.self))
            stats.add(lines: added.flatMap { a in removed.map { (a, $0) } })
        }
        return stats
    }

    static func lineCount(of contents: Data) -> Int? {
        if contents.prefix(8000).contains(0) { return nil }
        let newlines = contents.reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
        return contents.last.map { $0 == UInt8(ascii: "\n") ? newlines : newlines + 1 } ?? 0
    }
}

/// What the diff window compares: the session's starting commit against the working tree.
public struct DiffComparison: Equatable, Sendable {
    public var branch: String?
    public var baseline: String
    public var since: Date?
    public var baselineLeftHistory: Bool

    public init(branch: String?, baseline: String, since: Date?, baselineLeftHistory: Bool) {
        self.branch = branch
        self.baseline = baseline
        self.since = since
        self.baselineLeftHistory = baselineLeftHistory
    }

    /// e.g. "perf/x · since b08b00c at 13:26 → working tree", with `since` already formatted.
    public func summary(since formattedSince: String?) -> String {
        var parts = [branch ?? "detached HEAD"]
        parts.append("since \(baseline.prefix(7))\(formattedSince.map { " at \($0)" } ?? "") → working tree")
        if baselineLeftHistory { parts.append("branch changed since then") }
        return parts.joined(separator: " · ")
    }
}

public enum DiffSummary {
    public static func count(_ value: Int) -> String {
        value >= 1000 ? String(format: "%.1fk", Double(value) / 1000) : "\(value)"
    }

    public static func lines(_ stats: DiffStats, sharedWith others: Int) -> [String] {
        var lines: [String] = []
        if stats.files > 0 {
            let files = stats.files == 1 ? "1 file" : "\(stats.files) files"
            lines.append("\(files) changed since this session started (+\(stats.added) −\(stats.removed))")
        }
        if stats.binaryFiles > 0 {
            lines.append(stats.binaryFiles == 1 ? "1 binary file" : "\(stats.binaryFiles) binary files")
        }
        if stats.baselineLeftHistory {
            lines.append("The branch changed since this session started. Reset to count from here.")
        }
        if others > 0 {
            lines.append(others == 1 ? "Includes changes from 1 other session in this checkout"
                : "Includes changes from \(others) other sessions in this checkout")
        }
        return lines
    }
}
