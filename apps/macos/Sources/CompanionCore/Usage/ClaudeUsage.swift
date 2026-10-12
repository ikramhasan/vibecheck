import Foundation

// Ported from CodexBar's Claude OAuth usage fetcher (MIT, © Peter Steinberger):
// https://github.com/steipete/CodexBar/tree/main/Sources/CodexBarCore/Providers/Claude
public struct ClaudeUsage: UsageProvider {
    public let info = ProviderInfo(id: "claude", name: "Claude")
    let credentialsFile: URL
    let keychain: @Sendable () async -> Data?
    let now: @Sendable () -> Date

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        let configDirectory = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appending(path: ".claude")
        self.init(credentialsFile: configDirectory.appending(path: ".credentials.json"),
                  keychain: Self.readKeychain, now: Date.init)
    }

    init(credentialsFile: URL, keychain: @escaping @Sendable () async -> Data?, now: @escaping @Sendable () -> Date) {
        self.credentialsFile = credentialsFile
        self.keychain = keychain
        self.now = now
    }

    static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let signedOut = "Signed out. Run claude to sign in again"

    public func fetch() async throws -> UsageReport {
        let credentials = try await self.credentials()
        var request = URLRequest(url: Self.url, timeoutInterval: 30)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("vibecheck", forHTTPHeaderField: "User-Agent")
        return try await Self.report(UsageHTTP.send(request, signedOut: Self.signedOut), plan: credentials.plan)
    }

    struct Credentials: Equatable {
        var accessToken: String
        var plan: String?
    }

    func credentials() async throws -> Credentials {
        let file = Self.oauth(try? Data(contentsOf: credentialsFile))
        if let usable = usable(file) { return usable }
        let keychain = Self.oauth(await keychain())
        if let usable = usable(keychain) { return usable }
        if file?.accessToken?.isEmpty == false || keychain?.accessToken?.isEmpty == false {
            throw UsageError("Sign-in expired. Run claude to refresh it")
        }
        throw UsageError("Not signed in. Run claude to sign in")
    }

    private static func oauth(_ data: Data?) -> CredentialsFile.OAuth? {
        data.flatMap { try? JSONDecoder().decode(CredentialsFile.self, from: $0).claudeAiOauth }
    }

    private func usable(_ oauth: CredentialsFile.OAuth?) -> Credentials? {
        guard let oauth, let token = oauth.accessToken, !token.isEmpty, let expiresAt = oauth.expiresAt,
              Date(timeIntervalSince1970: expiresAt / 1000) > now() else { return nil }
        return Credentials(accessToken: token,
                           plan: Self.planName(subscription: oauth.subscriptionType, tier: oauth.rateLimitTier))
    }

    @Sendable static func readKeychain() async -> Data? {
        let output = try? await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/security"),
            ["find-generic-password", "-s", "Claude Code-credentials", "-w"],
            timeout: 5)
        guard let output, output.status == 0 else { return nil }
        return output.stdout
    }

    static func report(_ data: Data, plan: String?) throws -> UsageReport {
        let response = try UsageHTTP.decode(Response.self, from: data)
        var windows: [UsageWindow] = []
        func add(_ window: Response.Window?, minutes: Int, model: String? = nil) {
            guard let window, let used = window.utilization else { return }
            windows.append(UsageWindow(label: label(minutes: minutes, model: model),
                                       usedPercent: min(max(used, 0), 100),
                                       windowMinutes: minutes,
                                       resetsAt: window.resetsAt.flatMap(parseDate)))
        }
        add(response.fiveHour, minutes: 300)
        add(response.sevenDay, minutes: 10080)
        add(response.sevenDaySonnet, minutes: 10080, model: "Sonnet")
        add(response.sevenDayOpus, minutes: 10080, model: "Opus")
        for limit in response.limits ?? [] where limit.group == "weekly" && limit.kind == "weekly_scoped" {
            guard let model = limit.scope?.model?.displayName, !model.isEmpty,
                  !model.lowercased().hasPrefix("all models"),
                  !windows.contains(where: { $0.label == label(minutes: 10080, model: model) }) else { continue }
            add(Response.Window(utilization: limit.percent, resetsAt: limit.resetsAt), minutes: 10080, model: model)
        }
        guard !windows.isEmpty else { throw UsageError("No plan limits reported") }
        return UsageReport(plan: plan, windows: windows)
    }

    static func label(minutes: Int, model: String?) -> String {
        let length = UsageWindow.label(minutes: minutes)
        return model.map { "\($0) \(length)" } ?? length
    }

    static func planName(subscription: String?, tier: String?) -> String? {
        let words = (subscription ?? "").lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let tier = (tier ?? "").lowercased()
        for plan in ["max", "pro", "team", "enterprise"] where words.contains(Substring(plan)) {
            return plan == "max" ? maxPlan(tier: tier) : plan.capitalized
        }
        for plan in ["max", "pro", "team", "enterprise"] where tier.contains(plan) {
            return plan == "max" ? maxPlan(tier: tier) : plan.capitalized
        }
        return nil
    }

    private static func maxPlan(tier: String) -> String {
        let parts = tier.split(separator: "_")
        guard let index = parts.firstIndex(of: "max"), index + 1 < parts.count,
              parts[index + 1].hasSuffix("x"), Int(parts[index + 1].dropLast()) != nil else { return "Max" }
        return "Max \(parts[index + 1])"
    }

    static func parseDate(_ s: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: s) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: s)
    }

    private struct CredentialsFile: Decodable {
        let claudeAiOauth: OAuth?

        struct OAuth: Decodable {
            let accessToken: String?
            let expiresAt: Double?
            let subscriptionType: String?
            let rateLimitTier: String?
        }
    }

    private struct Response: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        let sevenDaySonnet: Window?
        let sevenDayOpus: Window?
        let limits: [Limit]?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour", sevenDay = "seven_day", sevenDaySonnet = "seven_day_sonnet"
            case sevenDayOpus = "seven_day_opus", limits
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fiveHour = try? c.decodeIfPresent(Window.self, forKey: .fiveHour)
            sevenDay = try? c.decodeIfPresent(Window.self, forKey: .sevenDay)
            sevenDaySonnet = try? c.decodeIfPresent(Window.self, forKey: .sevenDaySonnet)
            sevenDayOpus = try? c.decodeIfPresent(Window.self, forKey: .sevenDayOpus)
            limits = (try? c.decodeIfPresent([Lenient<Limit>].self, forKey: .limits))?.compactMap(\.value)
        }

        struct Window: Decodable {
            let utilization: Double?
            let resetsAt: String?
            enum CodingKeys: String, CodingKey { case utilization, resetsAt = "resets_at" }
        }

        struct Limit: Decodable {
            let kind: String?
            let group: String?
            let percent: Double?
            let resetsAt: String?
            let scope: Scope?
            enum CodingKeys: String, CodingKey { case kind, group, percent, resetsAt = "resets_at", scope }

            struct Scope: Decodable {
                let model: Model?
                struct Model: Decodable {
                    let displayName: String?
                    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
                }
            }
        }
    }
}

struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
