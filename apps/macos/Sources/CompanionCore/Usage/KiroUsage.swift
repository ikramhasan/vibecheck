import Foundation
import SQLite3

// Ported from CodexBar's Kiro usage-limits client (MIT, © Peter Steinberger):
// https://github.com/steipete/CodexBar/tree/main/Sources/CodexBarCore/Providers/Kiro
public struct KiroUsage: UsageProvider {
    public let info = ProviderInfo(id: "kiro", name: "Kiro")
    let database: URL
    let now: @Sendable () -> Date

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(database: home.appending(path: "Library/Application Support/kiro-cli/data.sqlite3"), now: Date.init)
    }

    init(database: URL, now: @escaping @Sendable () -> Date) {
        self.database = database
        self.now = now
    }

    static let signedOut = "Signed out. Run kiro-cli login"
    static let endpoints = [
        "us-east-1": URL(string: "https://codewhisperer.us-east-1.amazonaws.com/")!,
        "eu-central-1": URL(string: "https://q.eu-central-1.amazonaws.com/")!,
    ]

    public func fetch() async throws -> UsageReport {
        let credentials = try self.credentials()
        var request = URLRequest(url: credentials.endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.0", forHTTPHeaderField: "Content-Type")
        request.setValue("AmazonCodeWhispererService.GetUsageLimits", forHTTPHeaderField: "X-Amz-Target")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["profileArn": credentials.profileARN])
        return try await Self.report(UsageHTTP.send(request, signedOut: Self.signedOut))
    }

    struct Credentials: Equatable {
        var accessToken: String
        var profileARN: String
        var endpoint: URL
    }

    func credentials() throws -> Credentials {
        guard let rows = Self.read(database, [
            "SELECT value FROM auth_kv WHERE key = 'kirocli:odic:token'",
            "SELECT value FROM state WHERE key = 'api.codewhisperer.profile'",
        ]), let token = rows[0].flatMap({ try? JSONDecoder().decode(Token.self, from: $0) }),
              let accessToken = token.accessToken, !accessToken.isEmpty else {
            throw UsageError("Not signed in. Run kiro-cli login")
        }
        if let expiry = token.expiresAt.flatMap(ClaudeUsage.parseDate), expiry <= now() {
            throw UsageError("Sign-in expired. Run kiro-cli to refresh it")
        }
        guard let arn = rows[1].flatMap({ try? JSONDecoder().decode(Profile.self, from: $0) })?.arn,
              let endpoint = Self.endpoint(arn: arn) else {
            throw UsageError("No Kiro profile selected. Run kiro-cli")
        }
        return Credentials(accessToken: accessToken, profileARN: arn, endpoint: endpoint)
    }

    static func endpoint(arn: String) -> URL? {
        let parts = arn.split(separator: ":", maxSplits: 5, omittingEmptySubsequences: false)
        guard parts.count == 6, parts[0] == "arn", parts[1] == "aws", parts[2] == "codewhisperer",
              parts[5].hasPrefix("profile/") else { return nil }
        return endpoints[String(parts[3])]
    }

    static func read(_ database: URL, _ queries: [String]) -> [Data?]? {
        guard FileManager.default.isReadableFile(atPath: database.path) else { return nil }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        let uri = database.absoluteString + "?immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return nil }
        return queries.map { sql in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW,
                  let text = sqlite3_column_text(statement, 0) else { return nil }
            return Data(String(cString: text).utf8)
        }
    }

    static func report(_ data: Data) throws -> UsageReport {
        let response = try UsageHTTP.decode(Response.self, from: data)
        guard let credit = response.usageBreakdownList?.first(where: { $0.resourceType == "CREDIT" }),
              let total = credit.currentUsageWithPrecision, let limit = credit.usageLimitWithPrecision, limit > 0 else {
            throw UsageError("No plan limits reported")
        }
        let overage = credit.currentOveragesWithPrecision ?? 0
        let resetsAt = (credit.nextDateReset ?? response.nextDateReset).map(Date.init(timeIntervalSince1970:))
        var windows = [UsageWindow(label: "Monthly", usedPercent: min(max((total - overage) / limit * 100, 0), 100),
                                   windowMinutes: 43200, resetsAt: resetsAt)]
        if response.overageConfiguration?.overageStatus?.uppercased() == "ENABLED",
           let cap = credit.overageCapWithPrecision, cap > 0, overage > 0 {
            windows.append(UsageWindow(label: "Overage", usedPercent: min(overage / cap * 100, 100),
                                       windowMinutes: 43200, resetsAt: resetsAt))
        }
        return UsageReport(plan: response.subscriptionInfo?.subscriptionTitle.map(planName), windows: windows)
    }

    static func planName(_ title: String) -> String {
        title.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    private struct Token: Decodable {
        let accessToken: String?
        let expiresAt: String?
        enum CodingKeys: String, CodingKey { case accessToken = "access_token", expiresAt = "expires_at" }
    }

    private struct Profile: Decodable { let arn: String? }

    private struct Response: Decodable {
        let nextDateReset: Double?
        let overageConfiguration: OverageConfiguration?
        let subscriptionInfo: SubscriptionInfo?
        let usageBreakdownList: [Breakdown]?

        struct OverageConfiguration: Decodable { let overageStatus: String? }
        struct SubscriptionInfo: Decodable { let subscriptionTitle: String? }
        struct Breakdown: Decodable {
            let resourceType: String?
            let currentUsageWithPrecision: Double?
            let currentOveragesWithPrecision: Double?
            let usageLimitWithPrecision: Double?
            let overageCapWithPrecision: Double?
            let nextDateReset: Double?
        }
    }
}
