import CryptoKit
import Foundation
import Observation

public struct ActionRunKey: Hashable, Sendable {
    public var actionID: UUID
    public var directory: String

    public init(actionID: UUID, directory: String) {
        self.actionID = actionID
        self.directory = directory
    }
}

@MainActor
@Observable
public final class ActionStore {
    public private(set) var actions: [QuickAction]
    public private(set) var runs: [ActionRunKey: ActionRun] = [:]

    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logDirectory: URL
    @ObservationIgnored private let shell: String
    @ObservationIgnored private let captureEnvironment: @Sendable () -> [String: String]
    @ObservationIgnored private var environment: Task<[String: String], Never>?
    @ObservationIgnored private var pids: [ActionRunKey: Int32] = [:]
    @ObservationIgnored private var stopping: Set<ActionRunKey> = []

    static let key = "actions.saved"

    public static var defaultLogDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "vibecheck/actions", directoryHint: .isDirectory)
    }

    public init(defaults: UserDefaults = .standard, logDirectory: URL = ActionStore.defaultLogDirectory,
                shell: String = ShellEnvironment.userShell,
                environment: @escaping @Sendable () -> [String: String] = { ShellEnvironment.capture() }) {
        self.defaults = defaults
        self.logDirectory = logDirectory
        self.shell = shell
        captureEnvironment = environment
        actions = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([QuickAction].self, from: $0) } ?? []
    }

    public var running: [ActionRunKey] { runs.filter(\.value.isRunning).map(\.key) }

    public func action(_ id: UUID) -> QuickAction? { actions.first { $0.id == id } }

    public func run(for action: QuickAction, in directory: String? = nil) -> ActionRun? {
        runs[key(action, directory)]
    }

    public func otherDirectories(of action: QuickAction) -> [String] {
        runs.keys.filter { $0.actionID == action.id && $0.directory != action.directory }.map(\.directory).sorted()
    }

    public func save(_ action: QuickAction) {
        if let index = actions.firstIndex(where: { $0.id == action.id }) {
            actions[index] = action
        } else {
            actions.append(action)
        }
        persist()
    }

    public func delete(_ action: QuickAction) {
        let keys = runs.keys.filter { $0.actionID == action.id }
        keys.forEach(stop)
        actions.removeAll { $0.id == action.id }
        keys.filter { runs[$0]?.isRunning != true }.forEach(forget)
        persist()
    }

    public func run(_ action: QuickAction, in directory: String? = nil) {
        let key = key(action, directory)
        guard runs[key]?.isRunning != true else { return }
        guard QuickAction.isDirectory(key.directory) else { return finish(key, .failed("Folder not found")) }
        runs[key] = .running(startedAt: .now)
        onChange?()
        let environment = environmentTask()
        let log = logURL(for: key)
        let shell = shell
        Task {
            let variables = await environment.value
            guard !stopping.contains(key) else { return finish(key, .stopped) }
            let pid: Int32
            do {
                try FileManager.default.createDirectory(at: log.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                pid = try ActionProcess.launch(command: action.command, directory: key.directory,
                                               shell: shell, environment: variables, log: log)
            } catch {
                return finish(key, .failed("Couldn't start"))
            }
            pids[key] = pid
            let outcome = await withCheckedContinuation { continuation in
                Thread.detachNewThread { continuation.resume(returning: ActionProcess.waitForExit(pid)) }
            }
            pids[key] = nil
            finish(key, stopping.contains(key) ? .stopped : outcome)
        }
    }

    public func stop(_ action: QuickAction, in directory: String? = nil) {
        stop(key(action, directory))
    }

    public func dismiss(_ action: QuickAction, in directory: String) {
        let key = key(action, directory)
        guard runs[key]?.isRunning == false else { return }
        forget(key)
        onChange?()
    }

    public func stopAll() async {
        let pending = running
        pending.forEach(stop)
        while pending.contains(where: { runs[$0]?.isRunning == true }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    public func logURL(for action: QuickAction, in directory: String? = nil) -> URL {
        logURL(for: key(action, directory))
    }

    public func log(for action: QuickAction, in directory: String? = nil) -> String {
        ActionLog.read(logURL(for: action, in: directory))
    }

    private func key(_ action: QuickAction, _ directory: String?) -> ActionRunKey {
        ActionRunKey(actionID: action.id, directory: directory ?? action.directory)
    }

    private func stop(_ key: ActionRunKey) {
        guard runs[key]?.isRunning == true, stopping.insert(key).inserted else { return }
        guard let pid = pids[key] else { return }
        Task {
            await ActionProcess.stop(pid) { @MainActor [weak self] in self?.pids[key] == pid }
        }
    }

    private func logURL(for key: ActionRunKey) -> URL {
        let digest = SHA256.hash(data: Data(key.directory.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return logDirectory.appending(path: key.actionID.uuidString).appending(path: "\(digest).log")
    }

    private func finish(_ key: ActionRunKey, _ outcome: ActionRun.Outcome) {
        stopping.remove(key)
        if action(key.actionID) != nil {
            runs[key] = .finished(outcome, endedAt: .now)
        } else {
            forget(key)
        }
        onChange?()
    }

    private func forget(_ key: ActionRunKey) {
        runs[key] = nil
        try? FileManager.default.removeItem(at: logURL(for: key))
        let folder = logURL(for: key).deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func environmentTask() -> Task<[String: String], Never> {
        if let environment { return environment }
        let capture = captureEnvironment
        let task = Task.detached(priority: .userInitiated) { capture() }
        environment = task
        return task
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        defaults.set(data, forKey: Self.key)
        onChange?()
    }
}
