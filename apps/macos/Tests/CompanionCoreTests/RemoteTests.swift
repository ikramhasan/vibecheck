import Foundation
import Testing
@testable import CompanionCore

private func fixture(_ path: String) throws -> Data {
    try Data(contentsOf: try #require(Bundle.module.url(forResource: "Fixtures/\(path)", withExtension: nil)))
}

private let registry = Data(#"{"pid":660847,"sessionId":"f643b5a8-410b","cwd":"/home/me/Projects/Shop/app","entrypoint":"sdk-ts","status":"busy","startedAt":1791789997682}"#.utf8)
private let claudeTranscript = "/home/me/.claude/projects/-home-me-Projects-Shop-app/f643b5a8-410b.jsonl"

private func frame(_ header: String, _ body: Data = Data()) -> Data {
    Data("\(header)\n".utf8) + body
}

private func processBody(_ fields: [String: String]) -> Data {
    Data(fields.map { "\($0.key)=\($0.value)" }.joined(separator: "\n").utf8)
}

private func noLink(_ link: RemoteLink) -> Int32? { nil }

@Suite struct RemoteFrameParserTests {
    @Test func framesSplitAcrossReads() throws {
        let transcript = Data("{\"a\":1}\n".utf8)
        let stream = frame("V 2 8", Data("/home/me".utf8)) + frame("S 7 \(registry.count)", registry)
            + frame("T s1 start \(transcript.count) 1791791200", transcript) + frame("G 7") + frame("X 9")
            + frame("L 3", Data("1 a".utf8)) + frame("H s1 2", Data("{}".utf8)) + frame("E unsupported")
        var parser = RemoteFrameParser()
        var frames: [RemoteFrame] = []
        for byte in stream { frames += try parser.feed(Data([byte])) }
        #expect(frames == [
            .hello(home: "/home/me"),
            .registry(key: "7", registry),
            .transcript(key: "s1", .start, transcript, modifiedAt: Date(timeIntervalSince1970: 1_791_791_200)),
            .gone(key: "7"),
            .processGone(pid: 9),
            .piFiles(Data("1 a".utf8)),
            .firstLine(key: "s1", Data("{}".utf8)),
            .unsupported,
        ])
    }

    @Test func unexpectedOutputIsMalformed() {
        var parser = RemoteFrameParser()
        #expect(throws: RemoteFrameParser.Malformed.self) { try parser.feed(Data("Welcome to omarchy\n".utf8)) }
    }

    @Test func badLengthIsMalformed() {
        var parser = RemoteFrameParser()
        #expect(throws: RemoteFrameParser.Malformed.self) { try parser.feed(Data("S 7 -1\n".utf8)) }
    }
}

@Suite struct RemoteSessionsTests {
    @Test func claudeRegistryFollowsItsTranscript() {
        var sessions = RemoteSessions(host: "omaku")
        let commands = sessions.apply([.hello(home: "/home/me"), .registry(key: "660847", registry)])
        #expect(commands == ["F\ts1\t\(claudeTranscript)\n"])

        let session = try? #require(sessions.sessions(sshPID: noLink).first)
        #expect(session?.id == "claude/f643b5a8-410b@omaku")
        #expect(session?.host == "omaku")
        #expect(session?.pid == nil)
        #expect(session?.cwd == "/home/me/Projects/Shop/app")
        #expect(session?.status == .working)
    }

    @Test func nothingIsFollowedBeforeTheRemoteHomeIsKnown() {
        var sessions = RemoteSessions(host: "omaku")
        #expect(sessions.apply([.registry(key: "660847", registry)]).isEmpty)
    }

    @Test func registryUpdateKeepsFollowing() {
        var sessions = RemoteSessions(host: "omaku")
        _ = sessions.apply([.hello(home: "/home/me"), .registry(key: "660847", registry)])
        let idle = Data(String(decoding: registry, as: UTF8.self).replacingOccurrences(of: "busy", with: "idle").utf8)
        #expect(sessions.apply([.registry(key: "660847", idle)]).isEmpty)
        #expect(sessions.sessions(sshPID: noLink).first?.status == .idle)
    }

    @Test func pathsThatLeaveTheirFolderAreNotFollowed() {
        var sessions = RemoteSessions(host: "omaku")
        let hostile = Data(#"{"pid":1,"sessionId":"../../../.ssh/id","cwd":"/tmp"}"#.utf8)
        #expect(sessions.apply([.hello(home: "/home/me"), .registry(key: "1", hostile)]).isEmpty)
    }

    @Test func transcriptDrivesState() throws {
        var sessions = RemoteSessions(host: "omaku")
        _ = sessions.apply([.hello(home: "/home/me"), .registry(key: "660847", registry)])
        let modified = Date(timeIntervalSince1970: 1_791_791_200)
        _ = sessions.apply([.transcript(key: "s1", .start, try fixture("claude/running-tool.jsonl"), modifiedAt: modified)])
        #expect(sessions.sessions(sshPID: noLink).first?.status == .working)
        #expect(sessions.sessions(sshPID: noLink).first?.updatedAt == modified)

        _ = sessions.apply([.transcript(key: "s1", .tail, try fixture("claude/turn-ended.jsonl"), modifiedAt: modified)])
        let session = try #require(sessions.sessions(sshPID: noLink).first)
        #expect(session.status == .idle)
        #expect(session.lastReply == "Fixed it.")
    }

    @Test func appendedLinesCanArriveInPieces() throws {
        var sessions = RemoteSessions(host: "omaku")
        _ = sessions.apply([.hello(home: "/home/me"), .registry(key: "660847", registry)])
        let transcript = try fixture("claude/turn-ended.jsonl")
        let middle = transcript.count / 2
        _ = sessions.apply([.transcript(key: "s1", .start, transcript.prefix(middle), modifiedAt: .now),
                            .transcript(key: "s1", .more, transcript.dropFirst(middle), modifiedAt: .now)])
        #expect(sessions.sessions(sshPID: noLink).first?.lastReply == "Fixed it.")
    }

    @Test func goneRegistryUnfollows() {
        var sessions = RemoteSessions(host: "omaku")
        _ = sessions.apply([.hello(home: "/home/me"), .registry(key: "660847", registry)])
        #expect(sessions.apply([.gone(key: "660847")]) == ["U\ts1\n"])
        #expect(sessions.sessions(sshPID: noLink).isEmpty)
    }

    @Test func codexRolloutsOpenOnTheRemoteBecomeSessions() throws {
        var sessions = RemoteSessions(host: "omaku")
        let rollout = "/home/me/.codex/sessions/2026/10/11/rollout-2026-10-11T10-00-00-019c9446-4458-7ec0-980c-e2d97e99caf4.jsonl"
        let codex = processBody(["comm": "codex", "start": "1791790000", "cwd": "/home/me", "args": "codex",
                                 "files": rollout + "\u{1F}", "ssh": "", "ports": ""])
        #expect(sessions.apply([.hello(home: "/home/me"), .process(pid: 20, codex)]) == ["F\ts1\t\(rollout)\n"])

        let transcript = try fixture("codex/turn-complete.jsonl")
        let firstLine = try #require(transcript.split(separator: 0x0A).first.map { Data($0) })
        _ = sessions.apply([.firstLine(key: "s1", firstLine), .transcript(key: "s1", .start, transcript, modifiedAt: .now)])
        let session = try #require(sessions.sessions(sshPID: noLink).first)
        #expect(session.id == "codex/019c9446-4458-7ec0-980c-e2d97e99caf4@omaku")
        #expect(session.cwd == "/repo/shop")
        #expect(session.status == .idle)
        #expect(session.lastReply == "Done.")
    }

    @Test func piProcessesPickUpTheirSessionFile() throws {
        var sessions = RemoteSessions(host: "omaku")
        let file = "/home/me/.pi/agent/sessions/--home-me-site--/2026-10-11T10-00-00_01a126d0.jsonl"
        let pi = processBody(["comm": "pi", "start": "1791790000", "cwd": "/home/me/site", "args": "pi\u{1F}",
                              "env": "", "files": "", "ssh": "", "ports": ""])
        let commands = sessions.apply([.hello(home: "/home/me"), .process(pid: 30, pi),
                                       .piFiles(Data("1791790100.5 \(file)\n".utf8))])
        #expect(commands == ["F\ts1\t\(file)\n"])
        _ = sessions.apply([.transcript(key: "s1", .start, try fixture("pi/turn-ended.jsonl"), modifiedAt: .now)])
        let session = try #require(sessions.sessions(sshPID: noLink).first)
        #expect(session.agent == AgentIdentity.pi)
        #expect(session.cwd == "/home/me/site")
        #expect(session.status == .idle)
    }

    @Test func sessionsCarryTheLocalSSHProcess() {
        var sessions = RemoteSessions(host: "omaku")
        let claude = processBody(["comm": "claude", "start": "1791790000", "cwd": "/home/me/Projects/Shop/app",
                                  "args": "claude", "ssh": "100.1.1.1 51974 100.2.2.2 22", "ports": "3773"])
        _ = sessions.apply([.hello(home: "/home/me"), .registry(key: "660847", registry), .process(pid: 660847, claude)])
        let session = sessions.sessions { $0.listeningPorts == [3773] && $0.clientPort == 51974 ? 20131 : nil }.first
        #expect(session?.sshPID == 20131)
    }
}

@Suite struct RemoteJumpTests {
    private let omaku = "100.67.36.26"
    private func client(_ pid: Int32, _ arguments: [String], tty: String? = nil, localPort: UInt16 = 50000,
                        address: String = "100.67.36.26") -> LocalSSHClient {
        LocalSSHClient(pid: pid, arguments: ["ssh"] + arguments, tty: tty,
                       connections: [TCPConnection(localPort: localPort, remoteAddress: address, remotePort: 22)])
    }

    @Test func readsLoopbackForwards() {
        #expect(RemoteJump.forwardedPorts(["ssh", "-N", "-L", "52029:127.0.0.1:3773", "host"]) == [3773])
        #expect(RemoteJump.forwardedPorts(["ssh", "-L8080:localhost:80", "-L", "9000:[::1]:9001", "host"]) == [80, 9001])
        #expect(RemoteJump.forwardedPorts(["ssh", "-L", "8080:db.internal:5432", "host"]).isEmpty)
    }

    @Test func appTunnelToTheAgentsServerWins() {
        let t3 = client(1, ["-N", "-L", "52029:127.0.0.1:3773", "iku@omaku.ts.net"])
        let terminal = client(2, ["omaku"], tty: "/dev/ttys003", localPort: 51974)
        let link = RemoteLink(clientPort: 51974, serverPort: 22, listeningPorts: [3773])
        #expect(RemoteJump.sshPID(for: link, hostAddress: omaku, clients: [terminal, t3]) == 1)
    }

    @Test func sshConnectionMatchesTheTerminalSession() {
        let first = client(2, ["omaku"], tty: "/dev/ttys003", localPort: 51974)
        let second = client(3, ["omaku"], tty: "/dev/ttys004", localPort: 51990)
        let link = RemoteLink(clientPort: 51990, serverPort: 22)
        #expect(RemoteJump.sshPID(for: link, hostAddress: omaku, clients: [first, second]) == 3)
    }

    @Test func otherMachinesAreIgnored() {
        let elsewhere = client(4, ["-L", "1:127.0.0.1:3773", "other"], tty: "/dev/ttys005", address: "10.0.0.9")
        let link = RemoteLink(clientPort: 50000, serverPort: 22, listeningPorts: [3773])
        #expect(RemoteJump.sshPID(for: link, hostAddress: omaku, clients: [elsewhere]) == nil)
    }

    @Test func fallsBackToTheOnlyInteractiveSession() {
        let terminal = client(2, ["omaku"], tty: "/dev/ttys003")
        let tunnel = client(1, ["-N", "-L", "1:127.0.0.1:9999", "omaku"])
        #expect(RemoteJump.sshPID(for: RemoteLink(), hostAddress: omaku, clients: [terminal, tunnel]) == 2)
        let another = client(3, ["omaku"], tty: "/dev/ttys004")
        #expect(RemoteJump.sshPID(for: RemoteLink(), hostAddress: omaku, clients: [terminal, another]) == nil)
    }
}

@Suite struct RemoteProcessTests {
    @Test func parsesProcessFacts() throws {
        let body = processBody(["comm": "pi", "start": "1791790000", "cwd": "/home/me/site",
                                "args": "pi\u{1F}--session\u{1F}a b.jsonl\u{1F}", "env": "PI_SUBAGENT_CHILD=1",
                                "files": "", "ssh": "100.1.1.1 51974 100.2.2.2 22", "ports": "3773 8080"])
        let process = try #require(RemoteProcess(pid: 30, body: body))
        #expect(process.snapshot.name == PiDiscovery.processName)
        #expect(process.snapshot.arguments == ["pi", "--session", "a b.jsonl"])
        #expect(process.snapshot.environment == ["PI_SUBAGENT_CHILD": "1"])
        #expect(process.snapshot.startedAt == Date(timeIntervalSince1970: 1_791_790_000))
        #expect(process.link == RemoteLink(clientPort: 51974, serverPort: 22, listeningPorts: [3773, 8080]))
    }
}

@Suite struct RemoteHostTests {
    @Test func acceptsAliasesAndUserAtHost() {
        #expect(RemoteHost("omaku")?.alias == "omaku")
        #expect(RemoteHost(" iku@omaku.ragdoll-mine.ts.net ")?.alias == "iku@omaku.ragdoll-mine.ts.net")
        #expect(RemoteHost("ssh omaku")?.alias == "omaku")
    }

    @Test func rejectsAnythingSshCouldReadAsAnOption() {
        #expect(RemoteHost("-oProxyCommand=touch /tmp/x") == nil)
        #expect(RemoteHost("omaku bash") == nil)
        #expect(RemoteHost("omaku;rm") == nil)
        #expect(RemoteHost("") == nil)
    }

    @Test func sshNeverPromptsOrSharesAConnection() {
        let arguments = RemoteSessionSource.arguments(for: RemoteHost("omaku")!)
        #expect(arguments.contains("BatchMode=yes"))
        #expect(arguments.contains("ControlPath=none"))
        #expect(arguments.suffix(4) == ["--", "omaku", "bash", "-s"])
    }
}

@Suite struct LineBufferTests {
    @Test func tailDropsThePartialFirstLine() {
        var buffer = LineBuffer()
        let lines = buffer.restart(Data("ial\n{\"a\":1}\n{\"b\"".utf8), droppingFirstLine: true)
        #expect(lines == [Data("{\"a\":1}".utf8)])
        #expect(buffer.append(Data(":2}\n".utf8)) == [Data("{\"b\":2}".utf8)])
    }
}

@Suite struct RemoteReplyTests {
    @Test func repliesCarryBase64Output() throws {
        var parser = RemoteFrameParser()
        let output = Data("1\t2\ta.txt\0".utf8).base64EncodedString()
        let frames = try parser.feed(Data("R 3 0 \(output.utf8.count)\n\(output)R 4 255 0\n".utf8))
        #expect(frames == [
            .reply(id: 3, GitOutput(status: 0, stdout: Data("1\t2\ta.txt\0".utf8))),
            .reply(id: 4, GitOutput(status: 255, stdout: Data())),
        ])
    }
}

private actor FakeRemoteGit: GitReading {
    private(set) var queries: [GitQuery] = []
    private(set) var checkouts: Set<String> = []

    func run(_ query: GitQuery, in checkout: String) async -> GitOutput? {
        queries.append(query)
        checkouts.insert(checkout)
        let out: String = switch query {
        case .toplevel: "/home/me/repo\n"
        case .branch: "main\n"
        case .reflog, .head, .before: String(repeating: "a", count: 40) + "\n"
        case .numstat: "3\t1\tsrc/a.ts\0"
        case .untracked: "new.ts\0"
        case .isAncestor, .patch: ""
        }
        return GitOutput(status: 0, stdout: Data(out.utf8))
    }

    func contents(of path: String, in checkout: String) async -> Data? { Data("one\ntwo\n".utf8) }
}

@MainActor
@Suite(.serialized) struct RemoteDiffStatsTests {
    @Test func remoteSessionsCountChangesOnTheirMachine() async throws {
        let git = FakeRemoteGit()
        var localLookups: [String] = []
        let store = DiffStatsStore(computer: nil, repository: { localLookups.append($0); return nil },
                                   remoteGit: { $0 == "omaku" ? git : nil },
                                   defaults: UserDefaults(suiteName: UUID().uuidString)!, watchCheckouts: false)
        var session = AgentSession(agent: AgentIdentity.claude, sessionID: "s", cwd: "/home/me/repo/app",
                                   status: .working, startedAt: Date(timeIntervalSince1970: 1000))
        session.host = "omaku"
        store.update([session])
        try await Task.sleep(for: .milliseconds(200))

        #expect(store.stats(for: session) == DiffStats(files: 2, added: 5, removed: 1))
        #expect(await git.checkouts == ["/home/me/repo/app", "/home/me/repo"])
        #expect(await git.queries.contains(.reflog(at: 1000)))
        #expect(localLookups.isEmpty)
    }
}

@Suite struct RemoteServerTests {
    private func line(_ pid: Int32, _ parent: Int32, ports: String = "", exe: String, cwd: String = "/home/me/app",
                      args: [String], session: String = "") -> String {
        ["\(pid)", "\(parent)", "1791795523", ports, exe, cwd, args.joined(separator: "\u{1D}") + "\u{1D}", session]
            .joined(separator: "\u{1F}")
    }

    private var facts: RemoteServerFacts {
        RemoteServerFacts(Data([
            line(10, 1, exe: "/usr/bin/just", args: ["just", "dev"], session: "abc"),
            line(20, 10, exe: "/usr/bin/node", cwd: "/home/me/app/frontend", args: ["node", "next", "dev"], session: "abc"),
            line(21, 20, ports: "3000 ", exe: "/usr/bin/node", cwd: "/home/me/app/frontend",
                 args: ["next-server (v16.3.8)", "", ""], session: "abc"),
            line(30, 1, ports: "l18789 l18789 ", exe: "/usr/bin/node", cwd: "/home/me", args: ["node", "gateway"]),
            line(40, 1, ports: "l3773 ", exe: "/home/me/.t3/t3", args: ["t3", "serve"]),
        ].joined(separator: "\n").utf8))
    }

    @Test func linuxServersAreNamedByTheirExecutable() throws {
        let servers = facts.servers(host: "omaku", address: "100.67.36.26", agentPIDs: [])
        let next = try #require(servers.first { $0.ports == [3000] })
        #expect(next.id == "omaku:20")
        #expect(next.framework == .nextjs)
        #expect(next.cwd == "/home/me/app/frontend")
        #expect(next.address == "omaku:3000")
        #expect(next.url == URL(string: "http://100.67.36.26:3000"))
        #expect(!next.canStop)
        #expect(!servers.contains { $0.ports == [3773] })
    }

    @Test func loopbackOnlyServersHaveNoURL() throws {
        let gateway = try #require(facts.servers(host: "omaku", address: "100.67.36.26", agentPIDs: [])
            .first { $0.ports == [18789] })
        #expect(gateway.url == nil)
    }

    @Test func serversBelongToSessionsOnTheirOwnMachine() throws {
        let next = try #require(facts.servers(host: "omaku", address: nil, agentPIDs: []).first { $0.ports == [3000] })
        var remote = AgentSession(agent: AgentIdentity.claude, sessionID: "abc", cwd: "/home/me/app", status: .working)
        remote.host = "omaku"
        let local = AgentSession(agent: AgentIdentity.claude, sessionID: "abc", cwd: "/home/me/app", status: .working)
        #expect(next.wasStarted(by: remote))
        #expect(!next.wasStarted(by: local))
    }

    @Test func ipv6AddressesAreBracketed() {
        var server = DevServer(id: "x", framework: .node, pid: 1, startedAt: .now, ports: [3000])
        server.remote = DevServer.Remote(host: "omaku", address: "fd7a:115c::1")
        #expect(server.url == URL(string: "http://[fd7a:115c::1]:3000"))
    }
}
