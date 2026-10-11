import Darwin
import Foundation

public enum ShellEnvironment {
    static let timeout: TimeInterval = 10
    static let marker = "__VIBECHECK_ENV__"
    static let dropped: Set<String> = ["PWD", "OLDPWD", "SHLVL", "_"]

    public static var userShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        return "/bin/zsh"
    }

    public static func capture(shell: String = userShell) -> [String: String] {
        guard let output = run(shell, ["-ilc", "printf '%s' \(marker); /usr/bin/env -0"]),
              let parsed = parse(output), !parsed.isEmpty
        else { return ProcessInfo.processInfo.environment }
        return parsed
    }

    static func parse(_ output: Data) -> [String: String]? {
        let text = String(decoding: output, as: UTF8.self)
        guard let start = text.range(of: marker, options: .backwards) else { return nil }
        var environment: [String: String] = [:]
        for entry in text[start.upperBound...].split(separator: "\0") {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<equals])
            guard !key.isEmpty, !dropped.contains(key) else { continue }
            environment[key] = String(entry[entry.index(after: equals)...])
        }
        return environment
    }

    private static func run(_ shell: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let out = Pipe()
        process.standardOutput = out
        do { try process.run() } catch { return nil }

        let box = OutputBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.data = out.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return box.data
    }
}

private final class OutputBox: @unchecked Sendable {
    var data = Data()
}
