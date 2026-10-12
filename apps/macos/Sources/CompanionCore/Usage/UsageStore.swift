import Foundation
import Observation

public protocol UsageProvider: Sendable {
    var info: ProviderInfo { get }
    func fetch() async throws -> UsageReport
}

/// Usage for the providers the user enabled. Refreshes on a timer and on demand
/// (e.g. when the panel opens with stale data).
@MainActor
@Observable
public final class UsageStore {
    public let catalog: [ProviderInfo]
    /// Enabled providers, in the order the user sees them in Settings (by name).
    public private(set) var usage: [ProviderUsage] = []

    @ObservationIgnored private let providers: [String: UsageProvider]
    @ObservationIgnored private var enabled: Set<String> = []
    private var inFlight: Set<String> = []
    @ObservationIgnored private var lastFetch: [String: Date] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored public var refreshInterval: TimeInterval = 5 * 60
    /// Notified after `usage` changes (AppKit code that sizes the panel).
    @ObservationIgnored public var onChange: (([ProviderUsage]) -> Void)?

    public init(providers: [UsageProvider]) {
        self.providers = Dictionary(providers.map { ($0.info.id, $0) }, uniquingKeysWith: { a, _ in a })
        catalog = providers.map(\.info).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() { timer?.invalidate(); timer = nil }

    public func name(for id: String) -> String? { catalog.first { $0.id == id }?.name }

    public func supports(_ id: String) -> Bool { providers[id] != nil }

    /// Sync with Settings. Newly enabled providers are fetched immediately.
    public func setEnabled(_ ids: Set<String>) {
        let supported = ids.filter(supports)
        let added = supported.subtracting(enabled)
        enabled = supported
        rebuild()
        added.forEach(fetch)
    }

    public func refreshAll() { enabled.forEach(fetch) }

    public var isRefreshing: Bool { !inFlight.isEmpty }

    /// Refresh anything older than `maxAge` (used when the panel is opened).
    public func refreshIfStale(maxAge: TimeInterval = 120) {
        let now = Date()
        for id in enabled where now.timeIntervalSince(lastFetch[id] ?? .distantPast) > maxAge { fetch(id) }
    }

    private func rebuild() {
        let previous = Dictionary(usage.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let next = enabled.map { id -> ProviderUsage in
            previous[id] ?? ProviderUsage(id: id, name: name(for: id) ?? id)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        publish(next)
    }

    private func fetch(_ id: String) {
        guard let provider = providers[id], !inFlight.contains(id) else { return }
        inFlight.insert(id)
        lastFetch[id] = .now
        Task {
            let result: Result<UsageReport, Error>
            do { result = .success(try await provider.fetch()) } catch { result = .failure(error) }
            self.inFlight.remove(id)
            self.apply(id: id, result: result)
        }
    }

    private func apply(id: String, result: Result<UsageReport, Error>) {
        guard enabled.contains(id), let index = usage.firstIndex(where: { $0.id == id }) else { return }
        var u = usage[index]
        switch result {
        case .success(let report):
            u.state = .loaded
            u.plan = report.plan
            u.windows = report.windows
            u.updatedAt = .now
        case .failure(let error as UsageError):
            u.state = .failed(error.message)
            u.windows = []
            u.updatedAt = nil
        case .failure(let error):
            // Keep showing the last good reading through a network blip.
            if u.updatedAt == nil { u.state = .failed(error.localizedDescription) }
        }
        var next = usage
        next[index] = u
        publish(next)
    }

    private func publish(_ next: [ProviderUsage]) {
        guard next != usage else { return }
        usage = next
        onChange?(next)
    }
}
