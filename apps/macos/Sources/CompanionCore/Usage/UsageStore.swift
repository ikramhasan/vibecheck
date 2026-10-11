import Foundation
import Observation

/// Where usage data comes from. `CodexBarCLI` in the app; fakes in tests and `--demo`.
public protocol UsageFetching: Sendable {
    func providers() async throws -> [ProviderInfo]
    func usage(provider: String) async throws -> CodexBarDecoder.UsageEntry?
    func cost(provider: String) async throws -> CostSummary?
    func supportsCost(_ provider: String) -> Bool
}

extension CodexBarCLI: UsageFetching {
    public func supportsCost(_ provider: String) -> Bool { Self.costProviders.contains(provider) }
}

/// Provider catalog + usage for the providers the user enabled. Refreshes on a timer
/// and on demand (e.g. when the panel opens with stale data).
@MainActor
@Observable
public final class UsageStore {
    public enum CatalogState: Equatable, Sendable { case loading, loaded, unavailable(String) }

    public private(set) var catalog: [ProviderInfo] = []
    public private(set) var catalogState: CatalogState = .loading
    /// Enabled providers, in the order the user sees them in Settings (by name).
    public private(set) var usage: [ProviderUsage] = []

    @ObservationIgnored private let fetcher: UsageFetching?
    @ObservationIgnored private var enabled: Set<String> = []
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var lastFetch: [String: Date] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored public var refreshInterval: TimeInterval = 5 * 60
    /// Notified after `usage` changes (AppKit code that sizes the panel).
    @ObservationIgnored public var onChange: (([ProviderUsage]) -> Void)?

    /// `fetcher == nil` means the CLI couldn't be found.
    public init(fetcher: UsageFetching?) {
        self.fetcher = fetcher
        if fetcher == nil { catalogState = .unavailable("CodexBar CLI not found") }
    }

    public func start() {
        Task { await loadCatalog() }
        timer?.invalidate()
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() { timer?.invalidate(); timer = nil }

    public func name(for id: String) -> String? { catalog.first { $0.id == id }?.name }

    public func loadCatalog() async {
        guard let fetcher else { return }
        do {
            catalog = try await fetcher.providers().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            catalogState = .loaded
        } catch {
            catalogState = .unavailable(error.localizedDescription)
        }
        rebuild()
    }

    /// Sync with Settings. Newly enabled providers are fetched immediately.
    public func setEnabled(_ ids: Set<String>) {
        let added = ids.subtracting(enabled)
        enabled = ids
        rebuild()
        added.forEach(fetch)
    }

    public func refreshAll() { enabled.forEach(fetch) }

    /// Refresh anything older than `maxAge` (used when the panel is opened).
    public func refreshIfStale(maxAge: TimeInterval = 120) {
        let now = Date()
        for id in enabled where now.timeIntervalSince(lastFetch[id] ?? .distantPast) > maxAge { fetch(id) }
    }

    private func rebuild() {
        let previous = Dictionary(usage.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let next = enabled.map { id -> ProviderUsage in
            var u = previous[id] ?? ProviderUsage(id: id, name: id)
            u.name = name(for: id) ?? u.name
            return u
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        publish(next)
    }

    private func fetch(_ id: String) {
        guard let fetcher, !inFlight.contains(id) else { return }
        inFlight.insert(id)
        lastFetch[id] = .now
        Task {
            async let entryResult = capture { try await fetcher.usage(provider: id) }
            async let costResult: CostSummary? = fetcher.supportsCost(id) ? (try? await fetcher.cost(provider: id)) : nil
            let (entry, cost) = await (entryResult, costResult)
            self.inFlight.remove(id)
            self.apply(id: id, entry: entry, cost: cost)
        }
    }

    private func apply(id: String, entry: Result<CodexBarDecoder.UsageEntry?, Error>, cost: CostSummary?) {
        guard enabled.contains(id), let index = usage.firstIndex(where: { $0.id == id }) else { return }
        var u = usage[index]
        switch entry {
        case .success(let e?) where e.error != nil:
            u.state = .failed(e.error!)
        case .success(let e?):
            u.state = .loaded
            u.plan = e.plan
            u.windows = e.windows
            u.updatedAt = e.updatedAt ?? .now
        case .success(nil):
            u.state = .failed("No data")
        case .failure(let error):
            // Keep showing the last good reading through a transient failure.
            if u.updatedAt == nil { u.state = .failed(error.localizedDescription) }
        }
        u.cost = cost ?? u.cost
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

private func capture<T>(_ body: () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await body()) } catch { return .failure(error) }
}
