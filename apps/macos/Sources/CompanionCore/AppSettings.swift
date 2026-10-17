import Foundation
import Observation

/// Which thinking orb shows while an agent is working. The rendering lives in the app
/// target's `Orbs/`; Core only knows the catalog so settings can be persisted and tested.
public enum LoaderStyle: String, CaseIterable, Codable, Sendable {
    case random
    case working
    case gyro
    case reasoning
    case twins
    case searching
    case lighthouse
    case background
    case spiral

    public var displayName: String { rawValue.capitalized }

    public static let animations = allCases.filter { $0 != .random }

    public func resolved(seed: String) -> LoaderStyle {
        guard self == .random else { return self }
        let hash = seed.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return Self.animations[Int(hash % UInt64(Self.animations.count))]
    }
}

/// How status orbs are drawn: the dot-sphere thinking orbs, or ring orbs or buddy faces for every status.
public enum OrbFamily: String, CaseIterable, Codable, Sendable {
    case thinking
    case ring
    case buddy

    public var displayName: String {
        switch self {
        case .thinking: "Thinking"
        case .ring: "Ring"
        case .buddy: "Buddy"
        }
    }
}

/// Which loader to show: one global style, optionally overridden per agent id.
public struct LoaderSettings: Equatable, Sendable {
    public var global: LoaderStyle
    /// Agent id ("pi", "claude", …) → style. Absent means "use global".
    public var perAgent: [String: LoaderStyle]

    public init(global: LoaderStyle = .random, perAgent: [String: LoaderStyle] = [:]) {
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
        self.init(global: global ?? .random, perAgent: raw.compactMapValues(LoaderStyle.init(rawValue:)))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(global.rawValue, forKey: .global)
        try c.encode(perAgent.mapValues(\.rawValue), forKey: .perAgent)
    }
}

/// The agents the user has chosen to track, and what to show for each. Ids are the
/// agent ids session integrations report ("pi", "claude", "codex", …), which usage
/// providers share. Nothing is auto-detected: the user adds agents in Settings.
public struct AgentPreferences: Equatable, Codable, Sendable {
    /// Agents the user added, in the order they added them.
    public private(set) var added: [String]
    /// Opt-in per agent: each one costs a usage request every refresh.
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

public enum FinishedSessionRemoval: String, CaseIterable, Codable, Sendable {
    case instant, seconds30, minute1, minutes5, minutes10, minutes30, hour1, day1, never

    public static let `default` = FinishedSessionRemoval.minutes5

    public var delay: TimeInterval? {
        switch self {
        case .instant: 0
        case .seconds30: 30
        case .minute1: 60
        case .minutes5: 5 * 60
        case .minutes10: 10 * 60
        case .minutes30: 30 * 60
        case .hour1: 60 * 60
        case .day1: 24 * 60 * 60
        case .never: nil
        }
    }

    public var displayName: String {
        switch self {
        case .instant: "Instantly"
        case .seconds30: "After 30 seconds"
        case .minute1: "After 1 minute"
        case .minutes5: "After 5 minutes"
        case .minutes10: "After 10 minutes"
        case .minutes30: "After 30 minutes"
        case .hour1: "After 1 hour"
        case .day1: "After 1 day"
        case .never: "Never"
        }
    }
}

/// User preferences, persisted to UserDefaults. Grows a property per setting group.
@MainActor
@Observable
public final class AppSettings {
    public var loader: LoaderSettings {
        didSet { if loader != oldValue { save(loader, key: Keys.loader) } }
    }

    public var orbFamily: OrbFamily {
        didSet { if orbFamily != oldValue { defaults.set(orbFamily.rawValue, forKey: Keys.orbFamily) } }
    }

    public var agents: AgentPreferences {
        didSet { if agents != oldValue { save(agents, key: Keys.agents) } }
    }

    public var finishedSessionRemoval: FinishedSessionRemoval {
        didSet { if finishedSessionRemoval != oldValue { defaults.set(finishedSessionRemoval.rawValue, forKey: Keys.finishedSessionRemoval) } }
    }

    public var sounds: SoundSettings {
        didSet { if sounds != oldValue { save(sounds, key: Keys.sounds) } }
    }

    /// ssh destinations whose agent sessions the panel shows alongside this Mac's.
    public var remoteHosts: [RemoteHost] {
        didSet { if remoteHosts != oldValue { save(remoteHosts, key: Keys.remoteHosts) } }
    }

    public var hasCompletedOnboarding: Bool {
        didSet { if hasCompletedOnboarding != oldValue { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded) } }
    }

    public var panelPlacement: PanelPlacement {
        didSet { if panelPlacement != oldValue { save(panelPlacement, key: Keys.panelPlacement) } }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let loader = "settings.loader"
        static let orbFamily = "settings.orbFamily"
        static let agents = "settings.agents"
        static let finishedSessionRemoval = "settings.finishedSessionRemoval"
        static let sounds = "settings.sounds"
        static let remoteHosts = "settings.remoteHosts"
        static let onboarded = "settings.onboarded"
        static let panelPlacement = "settings.panelPlacement"
        static let stored = [loader, orbFamily, agents, finishedSessionRemoval, sounds, remoteHosts]
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loader = Self.load(LoaderSettings.self, key: Keys.loader, from: defaults) ?? LoaderSettings()
        orbFamily = defaults.string(forKey: Keys.orbFamily).flatMap(OrbFamily.init(rawValue:)) ?? .thinking
        agents = Self.load(AgentPreferences.self, key: Keys.agents, from: defaults) ?? AgentPreferences()
        finishedSessionRemoval = defaults.string(forKey: Keys.finishedSessionRemoval)
            .flatMap(FinishedSessionRemoval.init(rawValue:)) ?? .default
        sounds = Self.load(SoundSettings.self, key: Keys.sounds, from: defaults) ?? .default
        remoteHosts = Self.load([RemoteHost].self, key: Keys.remoteHosts, from: defaults) ?? []
        panelPlacement = Self.load(PanelPlacement.self, key: Keys.panelPlacement, from: defaults) ?? PanelPlacement()
        hasCompletedOnboarding = defaults.object(forKey: Keys.onboarded) as? Bool
            ?? Keys.stored.contains { defaults.object(forKey: $0) != nil }
        defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
