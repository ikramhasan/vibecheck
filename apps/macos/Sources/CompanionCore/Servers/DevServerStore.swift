import Foundation
import Observation

@MainActor
@Observable
public final class DevServerStore {
    public static let backgroundScanInterval: TimeInterval = 10
    public static let visibleScanInterval: TimeInterval = 2

    public private(set) var servers: [DevServer] = []

    @ObservationIgnored public var onChange: (([DevServer]) -> Void)?
    @ObservationIgnored private let agentPIDs: @MainActor () -> Set<Int32>
    @ObservationIgnored private let scan: @Sendable (Set<Int32>) -> [DevServer]
    @ObservationIgnored private let remote: @MainActor () -> [DevServer]
    @ObservationIgnored private let terminate: @Sendable (DevServer, Set<Int32>) async -> Void
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var stopping: Set<String> = []

    public init(agentPIDs: @escaping @MainActor () -> Set<Int32>,
                scan: @escaping @Sendable (Set<Int32>) -> [DevServer] = DevServerScanner.scan,
                remote: @escaping @MainActor () -> [DevServer] = { [] },
                terminate: @escaping @Sendable (DevServer, Set<Int32>) async -> Void = DevServerStopper.stop) {
        self.agentPIDs = agentPIDs
        self.scan = scan
        self.remote = remote
        self.terminate = terminate
    }

    public func start() {
        schedule()
        refresh()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func setVisible(_ value: Bool) {
        guard value != visible else { return }
        visible = value
        schedule()
        if value { refresh() }
    }

    public func refresh() {
        guard !scanning else { return }
        scanning = true
        let pids = agentPIDs()
        let scan = scan
        Task {
            let found = await Task.detached(priority: .utility) { scan(pids) }.value
            scanning = false
            publish(found + remote())
        }
    }

    public func stopServer(_ server: DevServer) {
        guard server.canStop, !stopping.contains(server.id) else { return }
        stopping.insert(server.id)
        publish(servers)
        let pids = agentPIDs()
        let terminate = terminate
        Task {
            await Task.detached(priority: .userInitiated) { await terminate(server, pids) }.value
            stopping.remove(server.id)
            refresh()
        }
    }

    public func servers(startedBy session: AgentSession) -> [DevServer] {
        servers.filter { $0.wasStarted(by: session) }
    }

    private func publish(_ found: [DevServer]) {
        let next = found.filter { !stopping.contains($0.id) }
        guard next != servers else { return }
        servers = next
        onChange?(next)
    }

    private func schedule() {
        timer?.invalidate()
        let interval = visible ? Self.visibleScanInterval : Self.backgroundScanInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
