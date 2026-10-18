import Foundation

public enum ClaudeDiscovery {
    struct RegistryEntry: Decodable {
        var pid: Int32
        var sessionId: String
        var cwd: String
        var name: String?
        var status: String?
        var startedAt: Double?
        var statusUpdatedAt: Double?

        var startedDate: Date? { startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }

        var idleSince: Date? {
            guard status == "idle" else { return nil }
            return statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        }

        var transcriptPath: String { "\(ClaudeDiscovery.projectDirectoryName(cwd))/\(sessionId).jsonl" }

        func liveSession(transcript: URL?, origin: AgentSession.Origin?) -> LiveSession {
            LiveSession(agent: AgentIdentity.claude, sessionID: sessionId, format: .claude, transcript: transcript,
                        pid: pid, cwd: cwd, name: name, origin: origin, startedAt: startedDate,
                        statusWithoutTranscript: status == "busy" ? .working : .idle, idleSince: idleSince)
        }
    }

    public static func discover(claudeDirectory: URL, isAlive: (Int32) -> Bool,
                                process: (Int32) -> ProcessSnapshot?) -> [LiveSession] {
        let registry = claudeDirectory.appendingPathComponent("sessions", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: registry, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let entry = try? JSONDecoder().decode(RegistryEntry.self, from: data),
                  isAlive(entry.pid) else { return nil }
            let transcript = claudeDirectory
                .appendingPathComponent("projects", isDirectory: true)
                .appendingPathComponent(entry.transcriptPath)
            return entry.liveSession(transcript: FileManager.default.fileExists(atPath: transcript.path) ? transcript : nil,
                                     origin: process(entry.pid)?.origin)
        }
    }

    static func projectDirectoryName(_ cwd: String) -> String {
        String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }
}
