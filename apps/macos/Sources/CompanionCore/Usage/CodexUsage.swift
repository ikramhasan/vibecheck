import Foundation

// Ported from CodexBar's Codex OAuth usage fetcher (MIT, © Peter Steinberger):
// https://github.com/steipete/CodexBar/tree/main/Sources/CodexBarCore/Providers/Codex
public struct CodexUsage: UsageProvider {
    public let info = ProviderInfo(id: "codex", name: "Codex")
    let authFile: URL
    let now: @Sendable () -> Date

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(authFile: home.appending(path: ".codex/auth.json"), now: Date.init)
    }

    init(authFile: URL, now: @escaping @Sendable () -> Date) {
        self.authFile = authFile
        self.now = now
    }

    static let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let signedOut = "Signed out. Run codex to sign in again"

    public func fetch() async throws -> UsageReport {
        let auth = try credentials()
        var request = URLRequest(url: Self.url, timeoutInterval: 30)
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = auth.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return try await Self.report(UsageHTTP.send(request, signedOut: Self.signedOut))
    }

    struct Credentials: Equatable {
        var accessToken: String
        var accountID: String?
    }

    func credentials() throws -> Credentials {
        guard let data = try? Data(contentsOf: authFile) else {
            throw UsageError("Not signed in. Run codex to sign in")
        }
        let file = try UsageHTTP.decode(AuthFile.self, from: data)
        guard let token = file.tokens?.accessToken, !token.isEmpty else {
            throw UsageError(file.apiKey?.isEmpty == false
                ? "Signed in with an API key, which has no plan limits"
                : "Not signed in. Run codex to sign in")
        }
        if let expiry = JWT.expiry(token), expiry <= now() {
            throw UsageError("Sign-in expired. Run codex to refresh it")
        }
        return Credentials(accessToken: token, accountID: file.tokens?.accountID.flatMap { $0.isEmpty ? nil : $0 })
    }

    static func report(_ data: Data) throws -> UsageReport {
        let response = try UsageHTTP.decode(Response.self, from: data)
        var windows = [response.rateLimit?.primaryWindow, response.rateLimit?.secondaryWindow]
            .compactMap { $0?.window(model: nil) }
            .sorted { ($0.windowMinutes ?? .max) < ($1.windowMinutes ?? .max) }
        for limit in response.additionalRateLimits ?? [] {
            let model = limit.limitName ?? limit.meteredFeature ?? "Extra"
            windows += [limit.rateLimit?.primaryWindow, limit.rateLimit?.secondaryWindow]
                .compactMap { $0?.window(model: model) }
        }
        guard !windows.isEmpty else { throw UsageError("No plan limits reported") }
        return UsageReport(plan: response.planType.map(planName), windows: windows)
    }

    static func planName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "pro": "Pro 20x"
        case "prolite", "pro_lite", "pro-lite": "Pro 5x"
        default: raw.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        }
    }

    private struct AuthFile: Decodable {
        let apiKey: String?
        let tokens: Tokens?

        struct Tokens: Decodable {
            let accessToken: String?
            let accountID: String?
            enum CodingKeys: String, CodingKey { case accessToken = "access_token", accountID = "account_id" }
        }

        enum CodingKeys: String, CodingKey { case apiKey = "OPENAI_API_KEY", tokens }
    }

    private struct Response: Decodable {
        let planType: String?
        let rateLimit: RateLimit?
        let additionalRateLimits: [AdditionalLimit]?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type", rateLimit = "rate_limit", additionalRateLimits = "additional_rate_limits"
        }

        struct RateLimit: Decodable {
            let primaryWindow: Window?
            let secondaryWindow: Window?
            enum CodingKeys: String, CodingKey { case primaryWindow = "primary_window", secondaryWindow = "secondary_window" }
        }

        struct AdditionalLimit: Decodable {
            let limitName: String?
            let meteredFeature: String?
            let rateLimit: RateLimit?
            enum CodingKeys: String, CodingKey {
                case limitName = "limit_name", meteredFeature = "metered_feature", rateLimit = "rate_limit"
            }
        }

        struct Window: Decodable {
            let usedPercent: Double?
            let limitWindowSeconds: Int?
            let resetAt: Double?
            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent", limitWindowSeconds = "limit_window_seconds", resetAt = "reset_at"
            }

            func window(model: String?) -> UsageWindow? {
                guard let usedPercent else { return nil }
                let minutes = limitWindowSeconds.flatMap { $0 > 0 ? $0 / 60 : nil }
                let length = UsageWindow.label(minutes: minutes)
                return UsageWindow(label: model.map { "\($0) \(length)" } ?? length,
                                   usedPercent: min(max(usedPercent, 0), 100),
                                   windowMinutes: minutes,
                                   resetsAt: resetAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil })
            }
        }
    }
}
