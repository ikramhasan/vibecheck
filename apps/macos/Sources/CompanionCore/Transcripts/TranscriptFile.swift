import Foundation

public struct TranscriptFile: Sendable {
    public static let initialWindow = 1 << 20

    public let url: URL
    private var offset: UInt64?
    private var buffer = LineBuffer()

    public init(url: URL) {
        self.url = url
    }

    public var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
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
        let start = restarted ? (size > UInt64(window) ? size - UInt64(window) : 0) : offset ?? 0
        guard (try? handle.seek(toOffset: start)) != nil else { return .appended([]) }
        let data = (try? handle.readToEnd()) ?? Data()
        offset = start + UInt64(data.count)
        return restarted
            ? .restarted(buffer.restart(data, droppingFirstLine: start > 0))
            : .appended(buffer.append(data))
    }
}
