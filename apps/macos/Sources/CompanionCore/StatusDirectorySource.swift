import Darwin
import Foundation

/// Reads the shared status directory that every reporter-based integration writes to.
/// Agent-agnostic: a new agent that writes files per the contract shows up here
/// without any app changes.
@MainActor
public final class StatusDirectorySource: SessionSource {
    public var onChange: (([AgentSession]) -> Void)?

    public let directory: URL
    /// Used only for files without a pid: drop them if not updated for this long.
    public var staleAfter: TimeInterval = 15 * 60
    /// Periodic rescan catches crashed processes (no file event happens when a pid dies).
    public var livenessInterval: TimeInterval = 2

    private var dirSource: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var pendingRescan = false
    private var last: [AgentSession] = []
    private let isAlive: (Int32) -> Bool

    public init(directory: URL = StatusDirectorySource.defaultDirectory(),
                isAlive: @escaping (Int32) -> Bool = ProcessLiveness.isAlive) {
        self.directory = directory
        self.isAlive = isAlive
    }

    /// Same resolution rules as `integrations/core/reporter.ts`.
    public nonisolated static func defaultDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let base: URL
        if let override = environment["VIBECHECK_DIR"], !override.isEmpty {
            base = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/vibecheck", isDirectory: true)
        }
        return base.appendingPathComponent("sessions", isDirectory: true)
    }

    public func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        watchDirectory()
        let timer = Timer(timeInterval: livenessInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        rescan()
    }

    public func stop() {
        dirSource?.cancel()
        dirSource = nil
        timer?.invalidate()
        timer = nil
    }

    private func watchDirectory() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRescan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        dirSource = source
    }

    /// Coalesce bursts of directory events (writes are tmp-file + rename).
    private func scheduleRescan() {
        guard !pendingRescan else { return }
        pendingRescan = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingRescan = false
                self?.rescan()
            }
        }
    }

    /// Exposed for tests.
    public func rescan() {
        let sessions = Self.scan(directory: directory, now: .now, staleAfter: staleAfter,
                                 isAlive: isAlive, pruneDead: true)
        guard sessions != last else { return }
        last = sessions
        onChange?(sessions)
    }

    nonisolated static func scan(directory: URL, now: Date, staleAfter: TimeInterval,
                                 isAlive: (Int32) -> Bool, pruneDead: Bool) -> [AgentSession] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [String: AgentSession] = [:]
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let session = try? StatusFileDecoder.decode(data) else { continue }
            let dead: Bool
            if let pid = session.pid {
                dead = !isAlive(pid)
            } else {
                dead = now.timeIntervalSince(session.updatedAt) > staleAfter
            }
            if dead {
                // Agent crashed or was killed before it could remove its file.
                if pruneDead { try? fm.removeItem(at: url) }
                continue
            }
            if let existing = result[session.id], existing.updatedAt >= session.updatedAt { continue }
            result[session.id] = session
        }
        return result.values.sorted { ($0.startedAt ?? $0.updatedAt) < ($1.startedAt ?? $1.updatedAt) }
    }
}

public enum ProcessLiveness {
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM // exists but owned by someone else
    }
}
