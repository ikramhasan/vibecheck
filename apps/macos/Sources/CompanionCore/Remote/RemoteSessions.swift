import Foundation

/// Agent sessions on one remote machine, built from `RemoteScript` frames with the same
/// discovery and transcript parsing as local sessions.
struct RemoteSessions {
    private struct Tracked {
        var live: LiveSession
        var key: String
        var lines = LineBuffer()
        var timeline = SessionTimeline()
        var updatedAt: Date
    }

    let host: String
    private var home: String?
    private var registries: [String: ClaudeDiscovery.RegistryEntry] = [:]
    private var processes: [Int32: RemoteProcess] = [:]
    private var piFiles: [PiDiscovery.SessionFile] = []
    private var serverFacts = RemoteServerFacts()
    private var codexCWDs: [String: String] = [:]
    private var tracked: [String: Tracked] = [:]
    private var nextKey = 0

    init(host: String) {
        self.host = host
    }

    /// Applies the frames and returns the commands to send back to the remote.
    mutating func apply(_ frames: [RemoteFrame]) -> [String] {
        frames.forEach { absorb($0) }
        return reconcile()
    }

    func sessions(sshPID: (RemoteLink) -> Int32?) -> [AgentSession] {
        tracked.values.map { entry in
            var session = entry.timeline.session(for: entry.live, updatedAt: entry.updatedAt)
            session.host = host
            session.pid = nil
            session.sshPID = processes[entry.live.pid].flatMap { sshPID($0.link) }
            return session
        }.sorted { ($0.startedAt ?? $0.updatedAt, $0.id) < ($1.startedAt ?? $1.updatedAt, $1.id) }
    }

    func servers(address: String?) -> [DevServer] {
        serverFacts.servers(host: host, address: address, agentPIDs: Set(processes.keys))
    }

    private mutating func absorb(_ frame: RemoteFrame) {
        switch frame {
        case .hello(let home):
            self.home = home
        case .unsupported, .reply:
            break
        case .registry(let key, let data):
            registries[key] = try? JSONDecoder().decode(ClaudeDiscovery.RegistryEntry.self, from: data)
        case .gone(let key):
            registries[key] = nil
        case .process(let pid, let body):
            processes[pid] = RemoteProcess(pid: pid, body: body)
        case .processGone(let pid):
            processes[pid] = nil
        case .piFiles(let listing):
            piFiles = RemoteProcess.piFiles(listing)
        case .serverFacts(let body):
            serverFacts = RemoteServerFacts(body)
        case .firstLine(let key, let line):
            guard let path = tracked.values.first(where: { $0.key == key })?.live.transcript?.path else { return }
            codexCWDs[path] = CodexTranscript.sessionCWD(from: line)
        case .transcript(let key, let read, let data, let modifiedAt):
            guard let id = tracked.first(where: { $0.value.key == key })?.key, var entry = tracked[id] else { return }
            let lines: [Data]
            switch read {
            case .start, .tail:
                entry.timeline = SessionTimeline()
                lines = entry.lines.restart(data, droppingFirstLine: read == .tail)
            case .more:
                lines = entry.lines.append(data)
            }
            entry.timeline.apply(lines.flatMap(entry.live.format.events(from:)))
            entry.updatedAt = modifiedAt
            tracked[id] = entry
        }
    }

    private mutating func reconcile() -> [String] {
        let found = Dictionary(discover().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var commands: [String] = []
        for (id, entry) in tracked where found[id] == nil {
            tracked[id] = nil
            commands.append("U\t\(entry.key)\n")
        }
        for (id, live) in found {
            if var entry = tracked[id] {
                let moved = entry.live.transcript != live.transcript
                entry.live = live
                if moved {
                    entry.lines = LineBuffer()
                    entry.timeline = SessionTimeline()
                    commands += Self.follow(entry.key, live.transcript)
                }
                tracked[id] = entry
            } else {
                nextKey += 1
                let key = "s\(nextKey)"
                tracked[id] = Tracked(live: live, key: key, updatedAt: live.startedAt ?? .now)
                commands += Self.follow(key, live.transcript)
            }
        }
        return commands
    }

    private static func follow(_ key: String, _ transcript: URL?) -> [String] {
        guard let path = transcript?.path, !path.contains("\t"), !path.contains("\n"), !"/\(path)/".contains("/../")
        else { return [] }
        return ["F\t\(key)\t\(path)\n"]
    }

    private func discover() -> [LiveSession] {
        guard let home else { return [] }
        let root = URL(fileURLWithPath: home, isDirectory: true)
        let processes = processes, piFiles = piFiles, codexCWDs = codexCWDs
        let snapshots = processes.values.map(\.snapshot)
        let claude = registries.values.map { entry in
            entry.liveSession(transcript: root.appending(path: ".claude/projects/" + entry.transcriptPath), origin: nil)
        }
        let codex = CodexDiscovery.discover(
            sessionsDirectory: root.appending(path: ".codex/sessions", directoryHint: .isDirectory),
            processes: snapshots, openFiles: { processes[$0]?.openFiles ?? [] }, sessionCWD: { codexCWDs[$0.path] })
        let pi = PiDiscovery.discover(
            sessionsDirectory: root.appending(path: ".pi/agent/sessions", directoryHint: .isDirectory),
            processes: snapshots,
            files: { directory in piFiles.filter { $0.url.deletingLastPathComponent().path == directory.path } })
        return claude + codex + pi
    }
}
