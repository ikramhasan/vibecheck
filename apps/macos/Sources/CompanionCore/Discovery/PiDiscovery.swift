import Foundation

public enum PiDiscovery {
    public static let processName = "node"

    public struct SessionFile: Equatable, Sendable {
        public var url: URL
        public var modifiedAt: Date

        public init(url: URL, modifiedAt: Date) {
            self.url = url
            self.modifiedAt = modifiedAt
        }
    }

    static let startSlack: TimeInterval = 5

    public static func discover(sessionsDirectory: URL, processes: [ProcessSnapshot],
                                files: (URL) -> [SessionFile]) -> [LiveSession] {
        let candidates = processes.filter(isInteractivePi)
        let byDirectory = Dictionary(grouping: candidates) { process in
            sessionsDirectory.appendingPathComponent(directoryName(process.cwd ?? "/"), isDirectory: true)
        }
        return byDirectory.flatMap { directory, processes in
            assign(processes: processes, files: files(directory)).map { process, file in
                LiveSession(agent: AgentIdentity.pi, sessionID: sessionID(fromFile: file), format: .pi, transcript: file,
                            pid: process.pid, cwd: process.cwd ?? "/", origin: process.origin,
                            startedAt: process.startedAt)
            }
        }
    }

    static func assign(processes: [ProcessSnapshot], files: [SessionFile]) -> [(ProcessSnapshot, URL)] {
        var available = files.sorted { $0.modifiedAt > $1.modifiedAt }
        var result: [(ProcessSnapshot, URL)] = []
        for process in processes.sorted(by: { $0.startedAt > $1.startedAt }) {
            if let explicit = explicitSessionFile(process) {
                available.removeAll { $0.url == explicit }
                result.append((process, explicit))
            } else if let index = available.firstIndex(where: { $0.modifiedAt >= process.startedAt.addingTimeInterval(-startSlack) }) {
                result.append((process, available.remove(at: index).url))
            }
        }
        return result
    }

    static func isInteractivePi(_ process: ProcessSnapshot) -> Bool {
        guard process.name == processName, process.environment["PI_SUBAGENT_CHILD"] != "1",
              isPiTitle(process.arguments.first) || isPiScript(process.arguments.dropFirst().first) else { return false }
        let args = process.arguments
        if args.contains("-p") || args.contains("--print") || args.contains("--no-session") { return false }
        if let mode = args.firstIndex(of: "--mode"), args.indices.contains(mode + 1), args[mode + 1] == "json" { return false }
        return true
    }

    private static func isPiTitle(_ argument: String?) -> Bool {
        argument == "pi"
    }

    private static func isPiScript(_ argument: String?) -> Bool {
        guard let argument else { return false }
        return argument.contains("pi-coding-agent") || (argument as NSString).lastPathComponent == "pi"
    }

    static func explicitSessionFile(_ process: ProcessSnapshot) -> URL? {
        guard let flag = process.arguments.firstIndex(of: "--session"),
              process.arguments.indices.contains(flag + 1) else { return nil }
        let value = process.arguments[flag + 1]
        guard value.hasSuffix(".jsonl") else { return nil }
        return value.hasPrefix("/") ? URL(fileURLWithPath: value)
            : URL(fileURLWithPath: process.cwd ?? "/").appendingPathComponent(value)
    }

    static func directoryName(_ cwd: String) -> String {
        let trimmed = cwd.hasPrefix("/") ? String(cwd.dropFirst()) : cwd
        return "--" + trimmed.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + "--"
    }

    static func sessionID(fromFile url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.split(separator: "_").last.map(String.init) ?? name
    }

    public static func sessionFiles(in directory: URL) -> [SessionFile] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "jsonl" }.compactMap { url in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
            return SessionFile(url: url, modifiedAt: date)
        }
    }
}
