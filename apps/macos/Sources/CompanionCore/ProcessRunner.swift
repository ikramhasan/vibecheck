import Foundation

enum ProcessRunner {
    enum Failure: Error {
        case launchFailed
        case timedOut
    }

    struct Output: Sendable {
        var status: Int32
        var stdout: Data
        var stderr: Data
    }

    static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result {
                    try runSync(executable, arguments, environment: environment, timeout: timeout)
                })
            }
        }
    }

    private static func runSync(_ executable: URL, _ arguments: [String], environment: [String: String]?,
                                timeout: TimeInterval) throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do { try process.run() } catch { throw Failure.launchFailed }

        // Drain both pipes concurrently so a chatty stderr can't fill its buffer and stall the child.
        let outBox = DataBox(), errBox = DataBox()
        let group = DispatchGroup()
        for (pipe, box) in [(out, outBox), (err, errBox)] {
            group.enter()
            DispatchQueue.global().async {
                box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            throw Failure.timedOut
        }
        process.waitUntilExit()
        return Output(status: process.terminationStatus, stdout: outBox.data, stderr: errBox.data)
    }
}

/// Written by exactly one reader thread, read only after `DispatchGroup.wait`.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}
