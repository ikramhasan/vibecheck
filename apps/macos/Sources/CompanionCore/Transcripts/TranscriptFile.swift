import Foundation

public struct TranscriptFile: Sendable {
    public static let initialWindow = 1 << 20

    public let url: URL
    private var offset: UInt64?
    private var partial = Data()

    public init(url: URL) {
        self.url = url
    }

    public enum Read: Equatable {
        case appended([Data])
        case restarted([Data])
    }

    public mutating func readNewLines(window: Int = TranscriptFile.initialWindow) -> Read {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .appended([]) }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let restarted = offset.map { size < $0 } ?? true
        var start = offset ?? 0
        if restarted {
            partial = Data()
            start = size > UInt64(window) ? size - UInt64(window) : 0
        }
        guard (try? handle.seek(toOffset: start)) != nil else { return .appended([]) }
        var data = (try? handle.readToEnd()) ?? Data()
        offset = start + UInt64(data.count)
        if restarted && start > 0, let newline = data.firstIndex(of: 0x0A) {
            data = data[data.index(after: newline)...]
        }
        let lines = split(partial + data)
        return restarted ? .restarted(lines) : .appended(lines)
    }

    private mutating func split(_ data: Data) -> [Data] {
        var lines: [Data] = []
        var lineStart = data.startIndex
        while let newline = data[lineStart...].firstIndex(of: 0x0A) {
            if newline > lineStart { lines.append(Data(data[lineStart..<newline])) }
            lineStart = data.index(after: newline)
        }
        partial = Data(data[lineStart...])
        return lines
    }
}
