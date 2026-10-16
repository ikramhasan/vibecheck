import Foundation
import Testing
@testable import CompanionCore

@Suite struct LoaderSettingsTests {
    @Test func agentFallsBackToGlobal() {
        var s = LoaderSettings(global: .gyro)
        #expect(s.style(for: "pi") == .gyro)
        s.setOverride(.spiral, for: "pi")
        #expect(s.style(for: "pi") == .spiral)
        #expect(s.style(for: "claude") == .gyro)
        s.setOverride(nil, for: "pi")
        #expect(s.style(for: "pi") == .gyro)
    }

    @Test func roundTripsThroughJSON() throws {
        let s = LoaderSettings(global: .gyro, perAgent: ["pi": .spiral])
        let decoded = try JSONDecoder().decode(LoaderSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }

    @Test func unknownStylesAreDroppedNotFatal() throws {
        let json = #"{"global":"nope","perAgent":{"pi":"gyro","claude":"gone"}}"#
        let s = try JSONDecoder().decode(LoaderSettings.self, from: Data(json.utf8))
        #expect(s.global == .random)
        #expect(s.perAgent == ["pi": .gyro])
    }

    @Test func randomIsTheDefault() {
        #expect(LoaderSettings().global == .random)
    }

    @Test func randomResolvesToAStableAnimationPerSeed() {
        let first = LoaderStyle.random.resolved(seed: "claude/abc")
        #expect(first != .random)
        #expect(LoaderStyle.random.resolved(seed: "claude/abc") == first)
        let seeds = (0..<200).map { "claude/session-\($0)" }
        #expect(Set(seeds.map { LoaderStyle.random.resolved(seed: $0) }) == Set(LoaderStyle.animations))
    }

    @Test func fixedStylesIgnoreTheSeed() {
        #expect(LoaderStyle.gyro.resolved(seed: "anything") == .gyro)
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
        first.loader.global = .gyro
        first.loader.setOverride(.spiral, for: "claude")

        let second = AppSettings(defaults: defaults)
        #expect(second.loader.global == .gyro)
        #expect(second.loader.style(for: "claude") == .spiral)
    }

    @Test func orbFamilyDefaultsToThinkingAndPersists() throws {
        let suite = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        #expect(first.orbFamily == .thinking)
        first.orbFamily = .ring

        #expect(AppSettings(defaults: defaults).orbFamily == .ring)
    }

    @Test func unknownOrbFamilyFallsBackToThinking() throws {
        let suite = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("gone", forKey: "settings.orbFamily")
        #expect(AppSettings(defaults: defaults).orbFamily == .thinking)
    }

    @Test func freshInstallNeedsOnboardingUntilCompleted() throws {
        let suite = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        #expect(!first.hasCompletedOnboarding)
        first.orbFamily = .ring
        #expect(!AppSettings(defaults: defaults).hasCompletedOnboarding)
        first.hasCompletedOnboarding = true

        #expect(AppSettings(defaults: defaults).hasCompletedOnboarding)
    }

    @Test func existingSettingsSkipOnboarding() throws {
        let suite = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("ring", forKey: "settings.orbFamily")
        #expect(AppSettings(defaults: defaults).hasCompletedOnboarding)
    }
}
