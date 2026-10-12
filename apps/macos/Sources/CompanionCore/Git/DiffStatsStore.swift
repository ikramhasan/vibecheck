import Foundation
import Observation

public enum DiffStatsRefresh {
    public static let minInterval: TimeInterval = 2
    static let resetLifetime: TimeInterval = 30 * 86400
}

@MainActor
@Observable
public final class DiffStatsStore {
    public private(set) var stats: [String: DiffStats] = [:]
    public private(set) var revisions: [String: Int] = [:]

    @ObservationIgnored private let computer: DiffStatsComputing?
    @ObservationIgnored private let repository: (String) -> String?
    @ObservationIgnored private let remoteGit: (String) -> GitReading?
    @ObservationIgnored private var resolvingRemote: [String: String] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var trackers: [String: Tracker] = [:]
    @ObservationIgnored private var watchers: [String: CheckoutWatcher] = [:]
    @ObservationIgnored private let watch: Bool

    private struct Tracker {
        var cwd: String
        var host: String?
        var checkout: String
        var computer: DiffStatsComputing
        var updatedAt: Date
        var working: Bool
        var baseline: String?
        var baselineSince: Date?
        var lastRun: Date?
        var running = false
        var runAgain = false
        var scheduled = false
    }

    private static let resetsKey = "diffBaselineResets"

    public init(computer: DiffStatsComputing?, repository: @escaping (String) -> String?,
                remoteGit: @escaping (String) -> GitReading? = { _ in nil },
                defaults: UserDefaults = .standard, watchCheckouts: Bool = true) {
        self.computer = computer
        self.repository = repository
        self.remoteGit = remoteGit
        self.defaults = defaults
        self.watch = watchCheckouts
        pruneResets()
    }

    public func stats(for session: AgentSession) -> DiffStats? {
        stats[session.id].flatMap { $0.isEmpty ? nil : $0 }
    }

    public func sessionsSharingCheckout(with session: AgentSession) -> Int {
        guard let tracker = trackers[session.id] else { return 0 }
        return trackers.values.filter { $0.checkout == tracker.checkout && $0.host == tracker.host }.count - 1
    }

    public func patches(for session: AgentSession) async -> [FilePatch]? {
        guard let tracker = trackers[session.id], let baseline = tracker.baseline else { return nil }
        return await tracker.computer.patches(in: tracker.checkout, since: baseline)
    }

    public func comparison(for session: AgentSession) async -> DiffComparison? {
        guard let tracker = trackers[session.id], let baseline = tracker.baseline else { return nil }
        let branch = await tracker.computer.branch(in: tracker.checkout)
        return DiffComparison(branch: branch, baseline: baseline, since: tracker.baselineSince,
                              baselineLeftHistory: stats[session.id]?.baselineLeftHistory ?? false)
    }

    public func update(_ sessions: [AgentSession]) {
        let current = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in trackers.keys where current[id] == nil {
            trackers[id] = nil
            stats[id] = nil
            revisions[id] = nil
        }
        for id in resolvingRemote.keys where current[id]?.cwd != resolvingRemote[id] { resolvingRemote[id] = nil }
        for (id, session) in current {
            let working = session.status == .working || session.status == .needsAttention
            if var tracker = trackers[id], tracker.cwd == session.cwd {
                let moved = tracker.updatedAt != session.updatedAt
                tracker.updatedAt = session.updatedAt
                tracker.working = working
                trackers[id] = tracker
                if moved { requestRefresh(id) }
            } else if session.host != nil {
                trackers[id] = nil
                resolveRemote(session)
            } else if let computer, let checkout = repository(session.cwd) {
                trackers[id] = Tracker(cwd: session.cwd, checkout: checkout, computer: computer,
                                       updatedAt: session.updatedAt, working: working)
                stats[id] = nil
                resolveBaseline(id, at: session.startedAt)
            } else {
                trackers[id] = nil
                stats[id] = nil
            }
        }
        updateWatchers()
    }

    public func resetBaseline(of session: AgentSession) {
        guard let tracker = trackers[session.id] else { return }
        let id = session.id, checkout = tracker.checkout, computer = tracker.computer
        Task {
            guard let head = await computer.baseline(in: checkout, at: nil),
                  trackers[id]?.checkout == checkout else { return }
            var resets = defaults.dictionary(forKey: Self.resetsKey) ?? [:]
            let now = Date.now
            resets[id] = ["baseline": head, "at": now]
            defaults.set(resets, forKey: Self.resetsKey)
            setBaseline(head, since: now, for: id)
        }
    }

    private func resolveRemote(_ session: AgentSession) {
        guard let host = session.host, resolvingRemote[session.id] == nil, let git = remoteGit(host) else { return }
        let id = session.id, cwd = session.cwd
        resolvingRemote[id] = cwd
        Task {
            guard let output = await git.run(.toplevel, in: cwd), output.status == 0 else { return }
            let checkout = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !checkout.isEmpty, resolvingRemote[id] == cwd, trackers[id] == nil else { return }
            let working = session.status == .working || session.status == .needsAttention
            trackers[id] = Tracker(cwd: cwd, host: host, checkout: checkout, computer: GitDiffStats(git: git),
                                   updatedAt: session.updatedAt, working: working)
            stats[id] = nil
            resolveBaseline(id, at: session.startedAt)
        }
    }

    private func resolveBaseline(_ id: String, at startedAt: Date?) {
        if let reset = defaults.dictionary(forKey: Self.resetsKey)?[id] as? [String: Any],
           let baseline = reset["baseline"] as? String {
            return setBaseline(baseline, since: reset["at"] as? Date, for: id)
        }
        guard let tracker = trackers[id] else { return }
        let checkout = tracker.checkout, computer = tracker.computer
        Task {
            guard let baseline = await computer.baseline(in: checkout, at: startedAt),
                  trackers[id]?.checkout == checkout else { return }
            setBaseline(baseline, since: startedAt, for: id)
        }
    }

    private func setBaseline(_ baseline: String, since: Date?, for id: String) {
        trackers[id]?.baseline = baseline
        trackers[id]?.baselineSince = since
        trackers[id]?.lastRun = nil
        requestRefresh(id)
    }

    private func requestRefresh(_ id: String) {
        guard let tracker = trackers[id], tracker.baseline != nil, !tracker.scheduled else { return }
        if tracker.running { trackers[id]?.runAgain = true; return }
        let wait = tracker.lastRun.map { $0.addingTimeInterval(DiffStatsRefresh.minInterval).timeIntervalSinceNow } ?? 0
        guard wait > 0 else { return run(id) }
        trackers[id]?.scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.trackers[id] != nil else { return }
                self.trackers[id]?.scheduled = false
                self.requestRefresh(id)
            }
        }
    }

    private func run(_ id: String) {
        guard let tracker = trackers[id], let baseline = tracker.baseline else { return }
        trackers[id]?.running = true
        trackers[id]?.lastRun = .now
        let checkout = tracker.checkout, computer = tracker.computer
        Task {
            let result = await computer.stats(in: checkout, since: baseline)
            guard trackers[id]?.checkout == checkout else { return }
            trackers[id]?.running = false
            if trackers[id]?.baseline == baseline, let result {
                if stats[id] != result { stats[id] = result }
                revisions[id, default: 0] += 1
            }
            if trackers[id]?.runAgain == true {
                trackers[id]?.runAgain = false
                requestRefresh(id)
            }
        }
    }

    private func checkoutChanged(_ checkout: String) {
        for (id, tracker) in trackers where tracker.host == nil && tracker.checkout == checkout { requestRefresh(id) }
    }

    private func updateWatchers() {
        guard watch else { return }
        let active = Set(trackers.values.filter { $0.working && $0.host == nil }.map(\.checkout))
        for (checkout, watcher) in watchers where !active.contains(checkout) {
            watcher.stop()
            watchers[checkout] = nil
        }
        for checkout in active where watchers[checkout] == nil {
            watchers[checkout] = CheckoutWatcher(checkout: checkout) { [weak self] in self?.checkoutChanged(checkout) }
        }
    }

    private func pruneResets() {
        guard let resets = defaults.dictionary(forKey: Self.resetsKey) else { return }
        let cutoff = Date.now.addingTimeInterval(-DiffStatsRefresh.resetLifetime)
        let kept = resets.filter { (($0.value as? [String: Any])?["at"] as? Date ?? .distantPast) > cutoff }
        if kept.count != resets.count { defaults.set(kept, forKey: Self.resetsKey) }
    }

    public func stop() {
        watchers.values.forEach { $0.stop() }
        watchers = [:]
    }
}
