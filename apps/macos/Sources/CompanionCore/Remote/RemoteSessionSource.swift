import Darwin
import Foundation
import Observation

/// An ssh destination as the user typed it, usually an alias from `~/.ssh/config`.
public struct RemoteHost: Hashable, Codable, Sendable {
    public let alias: String

    public init?(_ alias: String) {
        var alias = alias.trimmingCharacters(in: .whitespaces)
        if alias.hasPrefix("ssh ") { alias = alias.dropFirst(4).trimmingCharacters(in: .whitespaces) }
        guard let first = alias.first, first != "-",
              alias.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_@".contains($0)) })
        else { return nil }
        self.alias = alias
    }
}

/// Sessions of agents running on another machine, streamed over one long-lived ssh
/// connection. The remote side runs `RemoteScript`, which only reads.
@MainActor
@Observable
public final class RemoteSessionSource: SessionSource {
    public enum Connection: Equatable, Sendable {
        case connecting
        case connected
        case failed(String)
    }

    public let host: RemoteHost
    public private(set) var connection: Connection = .connecting
    @ObservationIgnored public private(set) var servers: [DevServer] = []
    @ObservationIgnored public var onChange: (([AgentSession]) -> Void)?

    static let firstRetryDelay: TimeInterval = 2
    static let maxRetryDelay: TimeInterval = 60
    private nonisolated static let environment = ShellEnvironment.capture()

    @ObservationIgnored private var running = false
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var parser = RemoteFrameParser()
    @ObservationIgnored private var sessions: RemoteSessions
    @ObservationIgnored private var errorOutput = Data()
    @ObservationIgnored private var retryDelay = RemoteSessionSource.firstRetryDelay
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var settle: SettleTimer?
    @ObservationIgnored private var last: [AgentSession] = []
    @ObservationIgnored private var nextQuery = 0
    @ObservationIgnored private var queries: [Int: CheckedContinuation<GitOutput?, Never>] = [:]
    @ObservationIgnored private var hostAddress: String?
    @ObservationIgnored private var unsupported = false

    public init(host: RemoteHost) {
        self.host = host
        self.sessions = RemoteSessions(host: host.alias)
        self.settle = SettleTimer { [weak self] in self?.publish() }
    }

    public func start() {
        guard !running else { return }
        running = true
        connect()
    }

    public func stop() {
        running = false
        retry?.cancel()
        retry = nil
        settle?.cancel()
        process?.terminate()
        process = nil
        input = nil
        failQueries()
        sessions = RemoteSessions(host: host.alias)
        servers = []
        publish()
    }

    /// Drops the connection and opens a new one right away, e.g. after the Mac wakes from sleep.
    public func reconnect() {
        guard running, !unsupported else { return }
        retry?.cancel()
        retryDelay = Self.firstRetryDelay
        if let process { process.terminate() } else { connect() }
    }

    /// Runs one of the read-only git queries the remote script allows. `nil` while disconnected.
    func query(_ op: String, in directory: String, argument: String = "") async -> GitOutput? {
        guard process != nil, [op, directory, argument].allSatisfy({ !$0.contains("\t") && !$0.contains("\n") })
        else { return nil }
        nextQuery += 1
        let id = nextQuery
        return await withCheckedContinuation { continuation in
            queries[id] = continuation
            send("Q\t\(id)\t\(op)\t\(directory)\t\(argument)\n")
        }
    }

    private func failQueries() {
        let pending = queries.values
        queries = [:]
        pending.forEach { $0.resume(returning: nil) }
    }

    nonisolated static func arguments(for host: RemoteHost) -> [String] {
        ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
         "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
         "-o", "ControlMaster=no", "-o", "ControlPath=none",
         "--", host.alias, "bash", "-s"]
    }

    private func connect() {
        Task.detached(priority: .utility) { [weak self] in
            let environment = Self.environment
            await self?.launch(environment: environment)
        }
    }

    private func launch(environment: [String: String]) {
        guard running, process == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = Self.arguments(for: host)
        process.environment = environment
        let input = Pipe(), output = Pipe(), error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(data, from: process) } }
        }
        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receivedError(data, from: process) } }
        }
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.disconnected(process) } }
        }

        parser = RemoteFrameParser()
        errorOutput = Data()
        do { try process.run() } catch {
            connection = .failed("Couldn't start ssh")
            scheduleRetry()
            return
        }
        self.process = process
        self.input = input.fileHandleForWriting
        send(RemoteScript.source)
    }

    private func send(_ text: String) {
        try? input?.write(contentsOf: Data(text.utf8))
    }

    private func received(_ data: Data, from process: Process) {
        guard process === self.process, !data.isEmpty else { return }
        do {
            let frames = try parser.feed(data)
            for frame in frames {
                switch frame {
                case .hello:
                    connection = .connected
                    retryDelay = Self.firstRetryDelay
                    hostAddress = ProcessScanner.tcpConnections(pid: process.processIdentifier).first?.remoteAddress
                case .unsupported:
                    unsupported = true
                    errorOutput = Data("Only Linux machines are supported".utf8)
                case .reply(let id, let output):
                    queries.removeValue(forKey: id)?.resume(returning: output)
                default:
                    break
                }
            }
            sessions.apply(frames).forEach(send)
            if frames.contains(where: { if case .serverFacts = $0 { true } else { false } }) {
                servers = sessions.servers(address: hostAddress)
            }
            settle?.changed()
        } catch {
            errorOutput = Data("Unexpected output from \(host.alias)".utf8)
            process.terminate()
        }
    }

    private func receivedError(_ data: Data, from process: Process) {
        guard process === self.process else { return }
        errorOutput.append(data)
    }

    private func disconnected(_ process: Process) {
        guard process === self.process else { return }
        self.process = nil
        input = nil
        hostAddress = nil
        let message = String(decoding: errorOutput, as: UTF8.self)
            .split(whereSeparator: \.isNewline).last.map(String.init)
        connection = .failed(message ?? "ssh exited with status \(process.terminationStatus)")
        failQueries()
        sessions = RemoteSessions(host: host.alias)
        servers = []
        settle?.cancel()
        publish()
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard running, !unsupported else { return }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, Self.maxRetryDelay)
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    private func publish() {
        let next = sessions.sessions(sshPID: localSSH())
        guard next != last else { return }
        last = next
        onChange?(next)
    }

    private func localSSH() -> (RemoteLink) -> Int32? {
        guard let hostAddress, let own = process?.processIdentifier else { return { _ in nil } }
        let clients = ProcessScanner.processes(named: ["ssh"]).filter { $0.pid != own }.map {
            LocalSSHClient(pid: $0.pid, arguments: $0.arguments, tty: $0.tty,
                           connections: ProcessScanner.tcpConnections(pid: $0.pid))
        }
        return { RemoteJump.sshPID(for: $0, hostAddress: hostAddress, clients: clients) }
    }
}
