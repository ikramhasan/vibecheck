import Foundation
import Observation

/// Identifier for a "working" loader in the loader library. The rendering lives in the
/// app target; Core only knows the catalog so settings can be persisted and tested.
/// Adding a loader = add a case here + a view in `Loaders/`.
public enum LoaderStyle: String, CaseIterable, Codable, Sendable {
    case ring
    case classic

    public var displayName: String {
        switch self {
        case .ring: "Ring"
        case .classic: "Classic"
        }
    }
}

/// Which loader to show: one global style, optionally overridden per agent id.
public struct LoaderSettings: Equatable, Sendable {
    public var global: LoaderStyle
    /// Agent id ("pi", "claude", …) → style. Absent means "use global".
    public var perAgent: [String: LoaderStyle]

    public init(global: LoaderStyle = .ring, perAgent: [String: LoaderStyle] = [:]) {
        self.global = global
        self.perAgent = perAgent
    }

    public func style(for agentID: String) -> LoaderStyle { perAgent[agentID] ?? global }

    /// `nil` clears the override so the agent follows the global style again.
    public mutating func setOverride(_ style: LoaderStyle?, for agentID: String) {
        perAgent[agentID] = style
    }
}

extension LoaderSettings: Codable {
    private enum CodingKeys: String, CodingKey { case global, perAgent }

    // Decoded leniently: a style that no longer exists (removed from the library, or
    // written by a newer build) falls back to the default instead of wiping settings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let global = (try? c.decode(String.self, forKey: .global)).flatMap(LoaderStyle.init(rawValue:))
        let raw = (try? c.decode([String: String].self, forKey: .perAgent)) ?? [:]
        self.init(global: global ?? .ring, perAgent: raw.compactMapValues(LoaderStyle.init(rawValue:)))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(global.rawValue, forKey: .global)
        try c.encode(perAgent.mapValues(\.rawValue), forKey: .perAgent)
    }
}

/// The agents the user has chosen to track, and what to show for each. Ids are CodexBar
/// provider ids, which are also the agent ids session integrations report ("pi",
/// "claude", "codex", …). Nothing is auto-detected: the user adds agents in Settings.
public struct AgentPreferences: Equatable, Codable, Sendable {
    /// Agents the user added, in the order they added them.
    public private(set) var added: [String]
    /// Opt-in per agent: each one costs a CodexBar fetch every refresh.
    public private(set) var usage: Set<String>
    /// Running status is shown unless hidden here, so an agent whose integration
    /// reports sessions keeps working even if it was never added.
    public private(set) var hiddenStatus: Set<String>

    public init(added: [String] = [], usage: Set<String> = [], hiddenStatus: Set<String> = []) {
        self.added = added
        self.usage = usage
        self.hiddenStatus = hiddenStatus
    }

    public func showsUsage(_ id: String) -> Bool { usage.contains(id) }
    public func showsStatus(_ id: String) -> Bool { !hiddenStatus.contains(id) }

    /// New agents start with usage on — that's usually why they're being added.
    public mutating func add(_ id: String) {
        guard !added.contains(id) else { return }
        added.append(id)
        usage.insert(id)
    }

    public mutating func remove(_ id: String) {
        added.removeAll { $0 == id }
        usage.remove(id)
        hiddenStatus.remove(id)
    }

    public mutating func setUsage(_ on: Bool, for id: String) {
        if on { usage.insert(id); if !added.contains(id) { added.append(id) } } else { usage.remove(id) }
    }

    public mutating func setStatus(_ on: Bool, for id: String) {
        if on { hiddenStatus.remove(id) } else {
            hiddenStatus.insert(id)
            if !added.contains(id) { added.append(id) }
        }
    }

    private enum CodingKeys: String, CodingKey { case added, usage, hiddenStatus }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(added: (try? c.decode([String].self, forKey: .added)) ?? [],
                  usage: (try? c.decode(Set<String>.self, forKey: .usage)) ?? [],
                  hiddenStatus: (try? c.decode(Set<String>.self, forKey: .hiddenStatus)) ?? [])
    }
}

public struct AlertSettings: Equatable, Codable, Sendable {
    public static let delayChoices = [0, 5, 10, 30, 60]

    public var delaySeconds: Int
    public var needsInput: Bool
    public var finished: Bool
    public var problems: Bool

    public init(delaySeconds: Int = 10, needsInput: Bool = true, finished: Bool = true, problems: Bool = true) {
        self.delaySeconds = delaySeconds
        self.needsInput = needsInput
        self.finished = finished
        self.problems = problems
    }

    private enum CodingKeys: String, CodingKey { case delaySeconds, needsInput, finished, problems }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AlertSettings()
        self.init(delaySeconds: (try? c.decode(Int.self, forKey: .delaySeconds)) ?? defaults.delaySeconds,
                  needsInput: (try? c.decode(Bool.self, forKey: .needsInput)) ?? defaults.needsInput,
                  finished: (try? c.decode(Bool.self, forKey: .finished)) ?? defaults.finished,
                  problems: (try? c.decode(Bool.self, forKey: .problems)) ?? defaults.problems)
    }
}

/// User preferences, persisted to UserDefaults. Grows a property per setting group.
@MainActor
@Observable
public final class AppSettings {
    public var loader: LoaderSettings {
        didSet { if loader != oldValue { save(loader, key: Keys.loader) } }
    }

    public var agents: AgentPreferences {
        didSet { if agents != oldValue { save(agents, key: Keys.agents) } }
    }

    public var alerts: AlertSettings {
        didSet { if alerts != oldValue { save(alerts, key: Keys.alerts) } }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let loader = "settings.loader"
        static let agents = "settings.agents"
        static let alerts = "settings.alerts"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loader = Self.load(LoaderSettings.self, key: Keys.loader, from: defaults) ?? LoaderSettings()
        agents = Self.load(AgentPreferences.self, key: Keys.agents, from: defaults) ?? AgentPreferences()
        alerts = Self.load(AlertSettings.self, key: Keys.alerts, from: defaults) ?? AlertSettings()
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
