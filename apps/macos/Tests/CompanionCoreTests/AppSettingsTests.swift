import Foundation
import Testing
@testable import CompanionCore

@Suite struct LoaderSettingsTests {
    @Test func agentFallsBackToGlobal() {
        var s = LoaderSettings(global: .classic)
        #expect(s.style(for: "pi") == .classic)
        s.setOverride(.ring, for: "pi")
        #expect(s.style(for: "pi") == .ring)
        #expect(s.style(for: "claude") == .classic)
        s.setOverride(nil, for: "pi")
        #expect(s.style(for: "pi") == .classic)
    }

    @Test func roundTripsThroughJSON() throws {
        let s = LoaderSettings(global: .classic, perAgent: ["pi": .ring])
        let decoded = try JSONDecoder().decode(LoaderSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }

    @Test func unknownStylesAreDroppedNotFatal() throws {
        let json = #"{"global":"nope","perAgent":{"pi":"classic","claude":"gone"}}"#
        let s = try JSONDecoder().decode(LoaderSettings.self, from: Data(json.utf8))
        #expect(s.global == .ring)
        #expect(s.perAgent == ["pi": .classic])
    }
}

@MainActor
@Suite struct AppSettingsTests {
    @Test func persistsAcrossInstances() throws {
        let suite = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        #expect(first.loader == LoaderSettings())
        first.loader.global = .classic
        first.loader.setOverride(.ring, for: "claude")

        let second = AppSettings(defaults: defaults)
        #expect(second.loader.global == .classic)
        #expect(second.loader.style(for: "claude") == .ring)
    }
}
