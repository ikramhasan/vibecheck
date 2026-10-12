import Foundation

enum RemoteFrame: Equatable {
    enum TranscriptRead: String {
        case start, tail, more
    }

    case hello(home: String)
    case unsupported
    case registry(key: String, Data)
    case gone(key: String)
    case process(pid: Int32, Data)
    case processGone(pid: Int32)
    case piFiles(Data)
    case serverFacts(Data)
    case firstLine(key: String, Data)
    case transcript(key: String, TranscriptRead, Data, modifiedAt: Date)
    case reply(id: Int, GitOutput)
}

struct RemoteFrameParser {
    struct Malformed: Error {}

    private var buffer = Data()

    mutating func feed(_ data: Data) throws -> [RemoteFrame] {
        buffer.append(data)
        var frames: [RemoteFrame] = []
        while let frame = try next() { frames.append(frame) }
        return frames
    }

    private mutating func next() throws -> RemoteFrame? {
        guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
        let fields = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self).split(separator: " ").map(String.init)
        let bodyStart = buffer.index(after: newline)
        switch (fields.first, fields.count) {
        case ("V", 3):
            guard fields[1] == "2" else { throw Malformed() }
            return try takeBody(length: fields[2], from: bodyStart).map { .hello(home: String(decoding: $0, as: UTF8.self)) }
        case ("E", 2):
            buffer = Data(buffer[bodyStart...])
            return .unsupported
        case ("G", 2):
            buffer = Data(buffer[bodyStart...])
            return .gone(key: fields[1])
        case ("X", 2):
            guard let pid = Int32(fields[1]) else { throw Malformed() }
            buffer = Data(buffer[bodyStart...])
            return .processGone(pid: pid)
        case ("S", 3):
            return try takeBody(length: fields[2], from: bodyStart).map { .registry(key: fields[1], $0) }
        case ("P", 3):
            guard let pid = Int32(fields[1]) else { throw Malformed() }
            return try takeBody(length: fields[2], from: bodyStart).map { .process(pid: pid, $0) }
        case ("L", 2):
            return try takeBody(length: fields[1], from: bodyStart).map { .piFiles($0) }
        case ("N", 2):
            return try takeBody(length: fields[1], from: bodyStart).map { .serverFacts($0) }
        case ("H", 3):
            return try takeBody(length: fields[2], from: bodyStart).map { .firstLine(key: fields[1], $0) }
        case ("T", 5):
            guard let read = RemoteFrame.TranscriptRead(rawValue: fields[2]),
                  let modified = TimeInterval(fields[4]) else { throw Malformed() }
            return try takeBody(length: fields[3], from: bodyStart)
                .map { .transcript(key: fields[1], read, $0, modifiedAt: Date(timeIntervalSince1970: modified)) }
        case ("R", 4):
            guard let id = Int(fields[1]), let status = Int32(fields[2]) else { throw Malformed() }
            guard let body = try takeBody(length: fields[3], from: bodyStart) else { return nil }
            guard let stdout = Data(base64Encoded: body) else { throw Malformed() }
            return .reply(id: id, GitOutput(status: status, stdout: stdout))
        default:
            throw Malformed()
        }
    }

    private mutating func takeBody(length: String, from start: Data.Index) throws -> Data? {
        guard let length = Int(length), length >= 0 else { throw Malformed() }
        guard buffer.distance(from: start, to: buffer.endIndex) >= length else { return nil }
        let end = buffer.index(start, offsetBy: length)
        let body = Data(buffer[start..<end])
        buffer = Data(buffer[end...])
        return body
    }
}
