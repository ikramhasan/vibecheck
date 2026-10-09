import Foundation

/// Decodes one status file written per `integrations/core/session-status.schema.json`.
public enum StatusFileDecoder {
    public static let supportedSchemaVersion = 1

    private struct File: Decodable {
        struct Session: Decodable {
            var id: String
            var cwd: String
            var name: String?
            var model: String?
        }
        var schemaVersion: Int
        var agent: AgentSession.AgentInfo
        var session: Session
        var pid: Int32?
        var origin: AgentSession.Origin?
        var status: AgentSession.Status
        var task: String?
        var activity: String?
        var attention: AgentSession.Attention?
        var startedAt: Date?
        var updatedAt: Date
    }

    public enum DecodeError: Error, Equatable {
        case unsupportedSchema(Int)
    }

    public static func decode(_ data: Data) throws -> AgentSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = parseISO8601(raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Bad date \(raw)"))
        }
        let file = try decoder.decode(File.self, from: data)
        guard file.schemaVersion == supportedSchemaVersion else {
            throw DecodeError.unsupportedSchema(file.schemaVersion)
        }
        return AgentSession(agent: file.agent, sessionID: file.session.id, cwd: file.session.cwd,
                            name: file.session.name.nonEmpty, model: file.session.model.nonEmpty,
                            pid: file.pid, origin: file.origin, status: file.status, task: file.task.nonEmpty,
                            activity: file.activity.nonEmpty, attention: file.attention,
                            startedAt: file.startedAt, updatedAt: file.updatedAt)
    }

    static func parseISO8601(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
