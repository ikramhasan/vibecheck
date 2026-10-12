import Foundation

public struct QuickAction: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var command: String
    public var directory: String

    public init(id: UUID = UUID(), name: String = "", command: String = "", directory: String = "") {
        self.id = id
        self.name = name
        self.command = command
        self.directory = directory
    }

    public var isComplete: Bool {
        [name, command, directory].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

public enum ActionRun: Equatable, Sendable {
    case running(startedAt: Date)
    case finished(Outcome, endedAt: Date)

    public enum Outcome: Equatable, Sendable {
        case exited(Int32)
        case stopped
        case signaled(Int32)
        case failed(String)

        public var succeeded: Bool { self == .exited(0) }

        public var summary: String {
            switch self {
            case .exited(0): "Done"
            case .exited(let code): "Exit \(code)"
            case .stopped: "Stopped"
            case .signaled(let signal): "Killed (signal \(signal))"
            case .failed(let message): message
            }
        }
    }

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
