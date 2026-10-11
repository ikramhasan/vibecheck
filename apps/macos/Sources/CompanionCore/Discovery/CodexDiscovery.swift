import Foundation

public enum CodexDiscovery {
    public static let processName = "codex"

    public static func discover(sessionsDirectory: URL, processes: [ProcessSnapshot],
                                openFiles: (Int32) -> [String], sessionCWD: (URL) -> String?) -> [LiveSession] {
        let root = sessionsDirectory.standardizedFileURL.path + "/"
        var seen = Set<String>()
        return processes.filter { $0.name == processName }.flatMap { process in
            openFiles(process.pid)
                .filter { $0.hasPrefix(root) && $0.hasSuffix(".jsonl") && seen.insert($0).inserted }
                .compactMap { path -> LiveSession? in
                    let url = URL(fileURLWithPath: path)
                    guard let id = sessionID(fromRollout: url) else { return nil }
                    return LiveSession(agent: AgentIdentity.codex, sessionID: id, format: .codex, transcript: url,
                                       pid: process.pid, cwd: sessionCWD(url) ?? process.cwd ?? "/",
                                       origin: process.origin, startedAt: process.startedAt)
                }
        }
    }

    static func sessionID(fromRollout url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("rollout-"), name.count > 36 else { return nil }
        return String(name.suffix(36))
    }
}
