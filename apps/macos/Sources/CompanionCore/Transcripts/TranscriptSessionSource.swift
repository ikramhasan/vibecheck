import Darwin
import Foundation

@MainActor
public final class TranscriptSessionSource: SessionSource {
    public var onChange: (([AgentSession]) -> Void)?
    public var discoveryInterval: TimeInterval = 2

    private let discovery: @Sendable () -> [LiveSession]
    private var trackers: [String: TranscriptTracker] = [:]
    private var timer: Timer?
    private var discovering = false
    private var last: [AgentSession] = []

    public init(discovery: SessionDiscovery = SessionDiscovery()) {
        self.discovery = { discovery.discover() }
    }

    init(discover: @escaping @Sendable () -> [LiveSession]) {
        self.discovery = discover
    }

    public func start() {
        let timer = Timer(timeInterval: discoveryInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.discover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        discover()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        trackers.values.forEach { $0.stop() }
        trackers = [:]
    }

    private func discover() {
        guard !discovering else { return }
        discovering = true
        let discovery = discovery
        Task.detached(priority: .utility) {
            let found = discovery()
            await MainActor.run { [weak self] in
                self?.discovering = false
                self?.reconcile(found)
            }
        }
    }

    func reconcile(_ found: [LiveSession]) {
        let current = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, tracker) in trackers where current[id] == nil {
            tracker.stop()
            trackers[id] = nil
        }
        for (id, live) in current {
            if let tracker = trackers[id] {
                tracker.update(live)
            } else {
                trackers[id] = TranscriptTracker(live: live) { [weak self] in self?.publish() }
            }
        }
        publish()
    }

    private func publish() {
        let sessions = trackers.values.map(\.session).sorted {
            ($0.startedAt ?? $0.updatedAt, $0.id) < ($1.startedAt ?? $1.updatedAt, $1.id)
        }
        guard sessions != last else { return }
        last = sessions
        onChange?(sessions)
    }
}

@MainActor
final class TranscriptTracker {
    private var live: LiveSession
    private var file: TranscriptFile?
    private var timeline = SessionTimeline()
    private var updatedAt: Date
    private var watcher: DispatchSourceFileSystemObject?
    private var settle: SettleTimer?
    private var reading = false
    private var readAgain = false
    private let onUpdate: () -> Void

    init(live: LiveSession, onUpdate: @escaping () -> Void) {
        self.live = live
        self.updatedAt = live.startedAt ?? .now
        self.onUpdate = onUpdate
        self.settle = SettleTimer { [weak self] in self?.read() }
        attach()
    }

    func update(_ next: LiveSession) {
        let transcriptChanged = next.transcript != live.transcript
        live = next
        if transcriptChanged {
            detach()
            file = nil
            timeline = SessionTimeline()
        }
        if watcher == nil { attach() }
    }

    func stop() {
        detach()
        settle?.cancel()
    }

    var session: AgentSession {
        AgentSession(agent: live.agent, sessionID: live.sessionID, cwd: live.cwd,
                     name: live.name ?? timeline.title, model: timeline.model, pid: live.pid, origin: live.origin,
                     status: timeline.hasEvents ? timeline.status : live.statusWithoutTranscript,
                     task: timeline.task, activity: timeline.activity, attention: timeline.attention,
                     context: timeline.context, wasInterrupted: timeline.wasInterrupted,
                     startedAt: live.startedAt, updatedAt: updatedAt)
    }

    private func attach() {
        guard let url = live.transcript else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        if file?.url != url { file = TranscriptFile(url: url) }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self, let source else { return }
                if source.data.contains(.delete) || source.data.contains(.rename) {
                    self.detach()
                } else {
                    self.settle?.changed()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
        read()
    }

    private func detach() {
        watcher?.cancel()
        watcher = nil
    }

    private func read() {
        guard let snapshot = file else { return }
        guard !reading else { readAgain = true; return }
        reading = true
        let format = live.format
        Task.detached(priority: .utility) {
            var file = snapshot
            let read = file.readNewLines()
            let modifiedAt = (try? file.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let (restarted, lines): (Bool, [Data]) = switch read {
            case .appended(let lines): (false, lines)
            case .restarted(let lines): (true, lines)
            }
            let events = lines.flatMap(format.events(from:))
            await self.finishRead(file: file, restarted: restarted, events: events, modifiedAt: modifiedAt)
        }
    }

    private func finishRead(file: TranscriptFile, restarted: Bool, events: [TranscriptEvent], modifiedAt: Date?) {
        reading = false
        guard self.file?.url == file.url else { return }
        self.file = file
        if restarted { timeline = SessionTimeline() }
        if restarted || !events.isEmpty {
            timeline.apply(events)
            updatedAt = modifiedAt ?? .now
            onUpdate()
        }
        if readAgain {
            readAgain = false
            read()
        }
    }
}
