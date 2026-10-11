import Foundation

public final class SessionDiscovery: @unchecked Sendable {
    private let home: URL
    private var codexCWDs: [URL: String] = [:]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func discover() -> [LiveSession] {
        let processes = ProcessScanner.processes(named: [CodexDiscovery.processName, PiDiscovery.processName])
        let claude = ClaudeDiscovery.discover(
            claudeDirectory: home.appendingPathComponent(".claude", isDirectory: true),
            isAlive: ProcessLiveness.isAlive, process: ProcessScanner.snapshot(pid:))
        let codex = CodexDiscovery.discover(
            sessionsDirectory: home.appendingPathComponent(".codex/sessions", isDirectory: true),
            processes: processes, openFiles: ProcessScanner.openFiles(pid:), sessionCWD: codexCWD)
        let pi = PiDiscovery.discover(
            sessionsDirectory: home.appendingPathComponent(".pi/agent/sessions", isDirectory: true),
            processes: processes, files: PiDiscovery.sessionFiles(in:))
        return claude + codex + pi
    }

    private func codexCWD(_ url: URL) -> String? {
        if let known = codexCWDs[url] { return known }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 512 * 1024)) ?? Data()
        let firstLine = head.split(separator: 0x0A, maxSplits: 1).first.map { Data($0) } ?? head
        let cwd = CodexTranscript.sessionCWD(from: firstLine)
        codexCWDs[url] = cwd
        return cwd
    }
}
