import Testing
@testable import CompanionCore

private let agent = ProcessNode(pid: 100, name: "node")

@Suite struct JumpResolverTests {
    @Test func nearestAppAboveTheAgent() {
        let tree = [agent, ProcessNode(pid: 90, name: "zsh"), ProcessNode(pid: 80, name: "login"),
                    ProcessNode(pid: 70, name: "Terminal", bundleId: "com.apple.Terminal")]
        #expect(JumpResolver.resolve(origin: nil, ancestry: tree) == JumpTarget(bundleId: "com.apple.Terminal", appPID: 70))
    }

    @Test func treeWinsOverReportedEnv() {
        // T3 Code spawned pi; the env's bundle id was inherited from somewhere else.
        let tree = [agent, ProcessNode(pid: 60, name: "T3 Code", bundleId: "com.t3tools.t3code")]
        let t = JumpResolver.resolve(origin: .init(bundleId: "com.apple.Terminal"), ancestry: tree)
        #expect(t == JumpTarget(bundleId: "com.t3tools.t3code", appPID: 60))
        #expect(t?.appName == "T3 Code")
    }

    @Test func reportedEnvWhenTreeIsBroken() {
        // tmux servers are children of launchd, so the tree never reaches the terminal.
        let tree = [agent, ProcessNode(pid: 50, name: "tmux")]
        #expect(JumpResolver.resolve(origin: .init(bundleId: "com.googlecode.iterm2", termProgram: "tmux"), ancestry: tree)
            == JumpTarget(bundleId: "com.googlecode.iterm2"))
    }

    @Test func termProgramFallback() {
        #expect(JumpResolver.resolve(origin: .init(termProgram: "ghostty"), ancestry: [])
            == JumpTarget(bundleId: "com.mitchellh.ghostty"))
    }

    @Test func nothingKnown() {
        #expect(JumpResolver.resolve(origin: nil, ancestry: [agent]) == nil)
        #expect(JumpResolver.resolve(origin: .init(termProgram: "tmux"), ancestry: []) == nil)
    }
}

@Suite struct TmuxTests {
    @Test func readsSocketAndServerFromEnvironment() {
        let env = "/private/tmp/tmux-501/default,4242,0"
        #expect(Tmux.socketPath(fromEnvironment: env) == "/private/tmp/tmux-501/default")
        #expect(Tmux.serverPID(fromEnvironment: env) == 4242)
        #expect(Tmux.socketPath(fromEnvironment: nil) == nil)
    }

    @Test func findsPaneByTTY() {
        let panes = "/dev/ttys004\tmain\t@1\t%1\n/dev/ttys007\twork\t@3\t%5\n"
        #expect(Tmux.pane(forTTY: "/dev/ttys007", in: panes) == .init(session: "work", window: "@3", pane: "%5"))
        #expect(Tmux.pane(forTTY: "/dev/ttys009", in: panes) == nil)
    }

    @Test func prefersMostRecentClientOnTheSameSession() {
        let clients = "/dev/ttys001\tmain\t300\t11\n/dev/ttys002\twork\t100\t12\n/dev/ttys003\twork\t200\t13\n"
        #expect(Tmux.bestClient(for: "work", in: clients)?.tty == "/dev/ttys003")
        #expect(Tmux.bestClient(for: "other", in: clients)?.tty == "/dev/ttys001")
    }
}
