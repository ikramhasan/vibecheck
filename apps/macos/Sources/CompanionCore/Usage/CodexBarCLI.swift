import Foundation

/// Runs the bundled CodexBar CLI. Every call is a one-shot process; nothing is
/// written to CodexBar's config, we only read.
public struct CodexBarCLI: Sendable {
    public enum Failure: Error, LocalizedError {
        case notFound
        case timedOut
        case exited(Int32, String)

        public var errorDescription: String? {
            switch self {
            case .notFound: "CodexBar CLI not found"
            case .timedOut: "CodexBar CLI timed out"
            case .exited(let code, let stderr):
                stderr.isEmpty ? "CodexBar CLI exited with \(code)" : stderr
            }
        }
    }

    public let executable: URL
    public var timeout: TimeInterval = 60

    public init(executable: URL) { self.executable = executable }

    /// Bundled helper first, then a dev override / Homebrew install so `swift run` works.
    public static func locate(bundle: Bundle = .main,
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> CodexBarCLI? {
        var candidates: [URL] = []
        if let override = environment["VIBECHECK_CODEXBAR"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        candidates.append(bundle.bundleURL.appending(path: "Contents/Helpers/CodexBarCLI"))
        candidates += ["/opt/homebrew/bin/codexbar", "/usr/local/bin/codexbar"].map { URL(fileURLWithPath: $0) }
        let fm = FileManager.default
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }.map(CodexBarCLI.init)
    }

    public func providers() async throws -> [ProviderInfo] {
        try CodexBarDecoder.providers(await run(["config", "providers", "--format", "json"]))
    }

    /// `--provider` accepts a single id per call (repeating it keeps only the last),
    /// so callers fan out one process per provider.
    public func usage(provider: String) async throws -> CodexBarDecoder.UsageEntry? {
        try CodexBarDecoder.usage(await run(["usage", "--provider", provider, "--format", "json", "--json-only"]))
            .first { $0.provider == provider } ?? nil
    }

    public func cost(provider: String) async throws -> CostSummary? {
        try CodexBarDecoder.cost(await run(["cost", "--provider", provider, "--format", "json", "--json-only"]))[provider]
    }

    /// Providers `codexbar cost` can report for (per its docs; others return an args error).
    public static let costProviders: Set<String> = ["claude", "codex", "cursor", "antigravity", "muse", "pi"]

    func run(_ arguments: [String]) async throws -> Data {
        let output: ProcessRunner.Output
        do {
            output = try await ProcessRunner.run(executable, arguments, timeout: timeout)
        } catch ProcessRunner.Failure.timedOut {
            throw Failure.timedOut
        } catch {
            throw Failure.notFound
        }
        // Per-provider failures come back as JSON with exit 0; only trust stdout when it parses.
        if output.status != 0 && output.stdout.isEmpty {
            let message = String(decoding: output.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.exited(output.status, String(message.prefix(300)))
        }
        return output.stdout
    }
}
