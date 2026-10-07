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

/// User preferences, persisted to UserDefaults. Grows a property per setting group.
@MainActor
@Observable
public final class AppSettings {
    public var loader: LoaderSettings {
        didSet { if loader != oldValue { save(loader, key: Keys.loader) } }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let loader = "settings.loader"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loader = Self.load(LoaderSettings.self, key: Keys.loader, from: defaults) ?? LoaderSettings()
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
