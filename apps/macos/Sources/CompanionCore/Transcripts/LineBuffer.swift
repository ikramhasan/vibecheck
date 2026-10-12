import Foundation

struct LineBuffer: Sendable {
    private var partial = Data()

    mutating func restart(_ data: Data, droppingFirstLine: Bool) -> [Data] {
        partial = Data()
        guard droppingFirstLine else { return append(data) }
        guard let newline = data.firstIndex(of: 0x0A) else { return [] }
        return append(data[data.index(after: newline)...])
    }

    mutating func append(_ data: Data) -> [Data] {
        let data = partial + data
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
