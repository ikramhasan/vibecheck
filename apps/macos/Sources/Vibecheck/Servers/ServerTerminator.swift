import AppKit
import CompanionCore

enum ServerTerminator {
    static let quitTimeout: Duration = .seconds(3)

    static func stop(_ server: DevServer, agentPIDs: Set<Int32>) async {
        guard server.appPath != nil else {
            await DevServerStopper.stop(server, agentPIDs: agentPIDs)
            return
        }
        guard server.canStop, !agentPIDs.contains(server.pid), isSameProcess(server) else { return }
        await MainActor.run { _ = NSRunningApplication(processIdentifier: server.pid)?.terminate() }
        let deadline = ContinuousClock.now + quitTimeout
        while isSameProcess(server), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func isSameProcess(_ server: DevServer) -> Bool {
        ProcessScanner.entry(pid: server.pid)?.startedAt == server.startedAt
    }
}
