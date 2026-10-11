import Foundation

public enum SoundEvent: String, CaseIterable, Codable, Sendable {
    case needsInput, finished, failed

    public var displayName: String {
        switch self {
        case .needsInput: "Needs input"
        case .finished: "Finished"
        case .failed: "Failed or hit a limit"
        }
    }

    public var defaultSound: String {
        switch self {
        case .needsInput: "Ping"
        case .finished: "Glass"
        case .failed: "Basso"
        }
    }
}

public struct SoundSettings: Equatable, Sendable {
    public static let `default` = SoundSettings()

    public var sounds: [SoundEvent: String?]
    public var volume: Double

    public init(sounds: [SoundEvent: String?] = [:], volume: Double = 0.8) {
        self.sounds = sounds
        self.volume = volume
    }

    public func sound(for event: SoundEvent) -> String? {
        sounds[event] ?? event.defaultSound
    }

    public mutating func setSound(_ name: String?, for event: SoundEvent) {
        sounds[event] = .some(name)
    }
}

extension SoundSettings: Codable {
    private enum CodingKeys: String, CodingKey { case sounds, volume }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decode([String: String].self, forKey: .sounds)) ?? [:]
        var sounds: [SoundEvent: String?] = [:]
        for (key, name) in raw {
            guard let event = SoundEvent(rawValue: key) else { continue }
            sounds[event] = name.isEmpty ? .some(nil) : .some(name)
        }
        self.init(sounds: sounds, volume: (try? c.decode(Double.self, forKey: .volume)) ?? Self.default.volume)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var raw: [String: String] = [:]
        for (event, name) in sounds { raw[event.rawValue] = name ?? "" }
        try c.encode(raw, forKey: .sounds)
        try c.encode(volume, forKey: .volume)
    }
}

public struct SoundPlanner: Sendable {
    public static let throttle: TimeInterval = 3

    private let launchedAt: Date
    private var previous: [String: AgentSession] = [:]
    private var lastPlayed: [SoundEvent: Date] = [:]

    public init(launchedAt: Date = .now) {
        self.launchedAt = launchedAt
    }

    public mutating func update(_ sessions: [AgentSession], now: Date = .now) -> [SoundEvent] {
        let events = Set(sessions.compactMap(event))
        previous = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return SoundEvent.allCases.filter { event in
            guard events.contains(event) else { return false }
            if let last = lastPlayed[event], now.timeIntervalSince(last) < Self.throttle { return false }
            lastPlayed[event] = now
            return true
        }
    }

    private func event(_ session: AgentSession) -> SoundEvent? {
        let old = previous[session.id]
        let since = session.statusSince ?? session.updatedAt
        switch session.status {
        case .needsAttention where session.attentionKey != old?.attentionKey && since >= launchedAt:
            return .needsInput
        case .idle where old?.status == .working && !session.wasInterrupted:
            return .finished
        case .blocked, .error:
            guard old?.status != session.status, since >= launchedAt else { return nil }
            return .failed
        default:
            return nil
        }
    }
}
