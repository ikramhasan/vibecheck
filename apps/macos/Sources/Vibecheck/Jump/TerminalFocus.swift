import AppKit
import CompanionCore
import OSLog

@MainActor
enum TerminalFocus {
    private static let log = Logger(subsystem: "com.ikramulhasan.vibecheck", category: "jump")

    static func supports(_ bundleId: String) -> Bool {
        script(bundleId: bundleId, tty: "") != nil
    }

    static func focus(tty: String, bundleId: String) -> Bool {
        guard let source = script(bundleId: bundleId, tty: tty) else { return false }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            log.info("Tab focus in \(bundleId, privacy: .public) failed: \(error, privacy: .public)")
            return false
        }
        return result?.booleanValue ?? false
    }

    private static func script(bundleId: String, tty: String) -> String? {
        let tty = tty.replacingOccurrences(of: "\"", with: "")
        switch bundleId {
        case "com.apple.Terminal":
            return """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            return """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        default:
            return nil
        }
    }
}

enum TmuxFocus {
    struct Host {
        var clientPID: Int32
        var clientTTY: String
    }

    static func focus(paneTTY: String, tmuxEnvironment: String) -> Host? {
        guard let socket = Tmux.socketPath(fromEnvironment: tmuxEnvironment),
              let server = Tmux.serverPID(fromEnvironment: tmuxEnvironment),
              let binary = ProcessScanner.executablePath(pid: server),
              let panes = run(binary, socket, ["list-panes", "-a", "-F", Tmux.paneFormat]),
              let pane = Tmux.pane(forTTY: paneTTY, in: panes),
              let clients = run(binary, socket, ["list-clients", "-F", Tmux.clientFormat]),
              let client = Tmux.bestClient(for: pane.session, in: clients) else { return nil }
        _ = run(binary, socket, ["switch-client", "-c", client.tty, "-t", pane.session])
        _ = run(binary, socket, ["select-window", "-t", pane.window])
        _ = run(binary, socket, ["select-pane", "-t", pane.pane])
        return Host(clientPID: client.pid, clientTTY: client.tty)
    }

    private static func run(_ binary: String, _ socket: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-S", socket] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
