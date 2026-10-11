import Foundation

public enum ClaudeDiscovery {
    private struct RegistryEntry: Decodable {
        var pid: Int32
        var sessionId: String
        var cwd: String
        var name: String?
        var status: String?
        var startedAt: Double?
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
                .appendingPathComponent(projectDirectoryName(entry.cwd), isDirectory: true)
                .appendingPathComponent("\(entry.sessionId).jsonl")
            return LiveSession(agent: AgentIdentity.claude, sessionID: entry.sessionId, format: .claude,
                               transcript: FileManager.default.fileExists(atPath: transcript.path) ? transcript : nil,
                               pid: entry.pid, cwd: entry.cwd, name: entry.name,
                               origin: process(entry.pid)?.origin,
                               startedAt: entry.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                               statusWithoutTranscript: entry.status == "busy" ? .working : .idle)
        }
    }

    static func projectDirectoryName(_ cwd: String) -> String {
        String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }
}
