import Darwin
import Foundation
import Testing
@testable import CompanionCore

@Suite struct DevServerClassificationTests {
    @Test(arguments: [
        ([["node", "/repo/node_modules/.bin/next", "dev"], ["next-server (v15.1.0)"]], DevServer.Framework.nextjs),
        ([["node", "/repo/node_modules/vite/bin/vite.js"]], .vite),
        ([["node", "/repo/node_modules/.bin/astro", "dev"]], .astro),
        ([["node", "/repo/node_modules/.bin/storybook", "dev", "-p", "6006"]], .storybook),
        ([["node", "/repo/node_modules/nuxi/bin/nuxi.mjs", "dev"]], .nuxt),
        ([["node", "/repo/node_modules/wrangler/bin/wrangler.js", "dev"],
          ["/repo/node_modules/@cloudflare/workerd-darwin-arm64/bin/workerd", "serve"]], .wrangler),
        ([["python3", "manage.py", "runserver"]], .django),
        ([["/repo/.venv/bin/python", "/repo/.venv/bin/flask", "run"]], .flask),
        ([["/repo/.venv/bin/python", "/repo/.venv/bin/uvicorn", "main:app", "--reload"]], .fastapi),
        ([["ruby", "bin/rails", "server"]], .rails),
        ([["puma 6.4.2 (tcp://localhost:3000) [shop]"]], .rails),
    ])
    func labelsFrameworks(arguments: [[String]], expected: DevServer.Framework) {
        #expect(DevServerScanner.framework(arguments: arguments) == expected)
    }

    @Test func unknownArgumentsFallBackToNil() {
        #expect(DevServerScanner.framework(arguments: [["node", "server.js"]]) == nil)
    }

    @Test func runtimesFromProcessNames() {
        #expect(DevServerScanner.runtime("node") == .node)
        #expect(DevServerScanner.runtime("Python") == .python)
        #expect(DevServerScanner.runtime("python3.12") == .python)
        #expect(DevServerScanner.runtime("ruby") == .ruby)
        #expect(DevServerScanner.runtime("com.docker.backe") == .docker)
        #expect(DevServerScanner.runtime("ControlCenter") == nil)
        #expect(DevServerScanner.runtime("zsh") == nil)
        #expect(DevServerScanner.runtime("claude") == nil)
    }

    @Test func findsTheOutermostAppBundleOfAMainExecutable() {
        #expect(DevServerScanner.appBundle(mainExecutable: "/r/build/My App.app/Contents/MacOS/My App") == "/r/build/My App.app")
        #expect(DevServerScanner.appBundle(mainExecutable: "/r/A.app/Contents/Frameworks/B.app/Contents/MacOS/B") == nil)
        #expect(DevServerScanner.appBundle(mainExecutable: "/r/A.app/Contents/Resources/tool") == nil)
        #expect(DevServerScanner.appBundle(mainExecutable: "/opt/homebrew/bin/node") == nil)
    }

    @Test func appBundlesAreNotDevServers() {
        #expect(DevServerScanner.isBundled("/Applications/Raycast.app/Contents/MacOS/Raycast Backend"))
        #expect(!DevServerScanner.isBundled("/opt/homebrew/Cellar/node/24.0.0/bin/node"))
        #expect(!DevServerScanner.isBundled(
            "/opt/homebrew/Cellar/python@3.13/3.13.1/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python"))
    }
}

@Suite struct DevServerScanTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func entry(_ pid: Int32, _ parent: Int32, _ name: String) -> ProcessEntry {
        ProcessEntry(pid: pid, parentPID: parent, name: name, startedAt: start)
    }

    private func scan(_ processes: [ProcessEntry], agentPIDs: Set<Int32> = [], ports: [Int32: [UInt16]] = [:],
                      executables: [Int32: String] = [:], snapshots: [Int32: ProcessSnapshot] = [:],
                      repositories: [String] = []) -> [DevServer] {
        DevServerScanner.servers(processes: processes, agentPIDs: agentPIDs, ownPID: 99,
                                 listeningPorts: { ports[$0] ?? [] }, executablePath: { executables[$0] },
                                 snapshot: { snapshots[$0] },
                                 isInRepository: { path in repositories.contains { path.hasPrefix($0 + "/") } })
    }

    @Test func listsAppsBuiltInsideARepository() {
        let processes = [entry(80, 1, "Vibecheck"), entry(81, 1, "Raycast"), entry(82, 80, "Helper"),
                         entry(83, 1, "Electron"), entry(84, 83, "claude")]
        let servers = scan(processes, agentPIDs: [84], executables: [
            80: "/Users/me/vibecheck/apps/macos/build/vibecheck.app/Contents/MacOS/Vibecheck",
            81: "/Applications/Raycast.app/Contents/MacOS/Raycast",
            82: "/Users/me/vibecheck/apps/macos/build/vibecheck.app/Contents/Helpers/Helper.app/Contents/MacOS/Helper",
            83: "/Users/me/desk/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron",
        ], repositories: ["/Users/me/vibecheck", "/Users/me/desk"])
        #expect(servers.map(\.name) == ["Electron", "vibecheck"])
        let vibecheck = servers.first { $0.pid == 80 }
        #expect(vibecheck?.framework == .app)
        #expect(vibecheck?.address == nil)
        #expect(vibecheck?.cwd == "/Users/me/vibecheck/apps/macos/build")
        #expect(vibecheck?.canStop == true)
        #expect(servers.first { $0.pid == 83 }?.canStop == false)
    }

    @Test func appsComeAfterServers() {
        let processes = [entry(90, 1, "node"), entry(91, 1, "Tool")]
        let servers = scan(processes, ports: [90: [3000]],
                           executables: [91: "/repo/build/Tool.app/Contents/MacOS/Tool"], repositories: ["/repo"])
        #expect(servers.map(\.framework) == [.node, .app])
    }

    @Test func groupsAServerTreeUnderItsTopRuntimeProcess() {
        let processes = [
            entry(10, 1, "Terminal"), entry(11, 10, "zsh"), entry(12, 11, "node"),
            entry(13, 12, "sh"), entry(14, 13, "node"), entry(15, 14, "node"),
        ]
        let servers = scan(processes, ports: [15: [3000], 14: [3000, 9229]], snapshots: [
            12: ProcessSnapshot(pid: 12, name: "node", arguments: ["npm", "run", "dev"]),
            14: ProcessSnapshot(pid: 14, name: "node", arguments: ["node", "/shop/node_modules/.bin/next", "dev"],
                                cwd: "/shop/apps/web"),
            15: ProcessSnapshot(pid: 15, name: "node", arguments: ["next-server (v15.1.0)"]),
        ])
        #expect(servers.count == 1)
        #expect(servers.first?.framework == .nextjs)
        #expect(servers.first?.pid == 14)
        #expect(servers.first?.ports == [3000, 9229])
        #expect(servers.first?.address == "localhost:3000")
        #expect(servers.first?.cwd == "/shop/apps/web")
        #expect(servers.first?.ancestorPIDs == [13, 12, 11, 10])
    }

    @Test func ignoresNonDevListeners() {
        let processes = [
            entry(20, 1, "ControlCenter"), entry(21, 1, "Raycast"), entry(22, 21, "node"),
            entry(23, 1, "node"), entry(24, 1, "ssh"),
        ]
        let servers = scan(processes, ports: [20: [5000, 7000], 22: [7265], 23: [58123], 24: [59200]],
                           executables: [21: "/Applications/Raycast.app/Contents/MacOS/Raycast",
                                         22: "/Users/me/Library/Application Support/com.raycast.macos/node/bin/node"])
        #expect(servers.isEmpty)
    }

    @Test func unknownServersShowTheirRuntime() {
        let servers = scan([entry(30, 1, "python3.12")], ports: [30: [8000]], snapshots: [
            30: ProcessSnapshot(pid: 30, name: "python3.12", arguments: ["python3", "-m", "http.server"]),
        ])
        #expect(servers.map(\.framework) == [.python])
    }

    @Test func dockerPortsAreSeparateRowsThatCannotStop() {
        let servers = scan([entry(40, 1, "com.docker.backe")], ports: [40: [5432, 8080]],
                           executables: [40: "/Applications/Docker.app/Contents/MacOS/com.docker.backend"])
        #expect(servers.map(\.id) == ["docker:5432", "docker:8080"])
        #expect(servers.allSatisfy { !$0.canStop })
    }

    @Test func neverClimbsIntoAnAgentProcess() {
        let processes = [entry(50, 1, "node"), entry(51, 50, "node")]
        let servers = scan(processes, agentPIDs: [50], ports: [50: [4000], 51: [5173]], snapshots: [
            51: ProcessSnapshot(pid: 51, name: "node", arguments: ["node", "vite"]),
        ])
        #expect(servers.map(\.pid) == [51])
        #expect(servers.first?.framework == .vite)
    }

    @Test func linksToTheSessionThatStartedIt() {
        let processes = [entry(60, 1, "claude"), entry(61, 60, "zsh"), entry(62, 61, "node"),
                         entry(70, 1, "zsh"), entry(71, 70, "node")]
        let servers = scan(processes, ports: [62: [5173], 71: [4321]], snapshots: [
            62: ProcessSnapshot(pid: 62, name: "node", arguments: ["vite"]),
            71: ProcessSnapshot(pid: 71, name: "node", arguments: ["astro", "dev"],
                                environment: ["CLAUDE_CODE_SESSION_ID": "abc"]),
        ])
        let byPID = Dictionary(uniqueKeysWithValues: servers.map { ($0.pid, $0) })
        let viaParent = AgentSession(agent: .init(id: "pi", name: "pi"), sessionID: "p", cwd: "/", pid: 60, status: .working)
        let claude = AgentSession(agent: AgentIdentity.claude, sessionID: "abc", cwd: "/", pid: 999, status: .working)
        #expect(byPID[62]?.wasStarted(by: viaParent) == true)
        #expect(byPID[62]?.wasStarted(by: claude) == false)
        #expect(byPID[71]?.wasStarted(by: claude) == true)
        #expect(byPID[71]?.wasStarted(by: viaParent) == false)
    }
}

@Suite struct DevServerStopperTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func entry(_ pid: Int32, _ parent: Int32, _ name: String) -> ProcessEntry {
        ProcessEntry(pid: pid, parentPID: parent, name: name, startedAt: start)
    }

    private func server(pid: Int32, startedAt: Date? = nil, framework: DevServer.Framework = .vite) -> DevServer {
        DevServer(id: "\(pid)", framework: framework, pid: pid, startedAt: startedAt ?? start, ports: [5173])
    }

    @Test func targetsTheServerTreeOnly() {
        let processes = [entry(1, 0, "launchd"), entry(10, 1, "zsh"), entry(11, 10, "node"),
                         entry(12, 11, "node"), entry(13, 12, "esbuild"), entry(14, 10, "node")]
        let pids = DevServerStopper.targets(of: server(pid: 11), processes: processes, agentPIDs: [], ownPID: 99).map(\.pid)
        #expect(pids == [11, 12, 13])
    }

    @Test func neverTargetsAgentsOrTheirChildren() {
        let processes = [entry(11, 1, "node"), entry(12, 11, "claude"), entry(13, 12, "zsh"),
                         entry(14, 11, "node"), entry(15, 14, "zsh"), entry(16, 11, "codex")]
        let pids = DevServerStopper.targets(of: server(pid: 11), processes: processes, agentPIDs: [14], ownPID: 99).map(\.pid)
        #expect(pids == [11])
        #expect(DevServerStopper.targets(of: server(pid: 14), processes: processes, agentPIDs: [14], ownPID: 99).isEmpty)
        #expect(DevServerStopper.targets(of: server(pid: 11), processes: processes, agentPIDs: [], ownPID: 11).isEmpty)
    }

    @Test func skipsReusedPIDsAndDocker() {
        let processes = [entry(11, 1, "node")]
        #expect(DevServerStopper.targets(of: server(pid: 11, startedAt: start.addingTimeInterval(5)),
                                         processes: processes, agentPIDs: [], ownPID: 99).isEmpty)
        #expect(DevServerStopper.targets(of: server(pid: 11, framework: .docker),
                                         processes: processes, agentPIDs: [], ownPID: 99).isEmpty)
    }
}

@Suite struct ListeningPortTests {
    @Test func findsThisProcessListeningSocket() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #expect(fd >= 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        #expect(bound == 0)
        #expect(listen(fd, 1) == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        let port = UInt16(bigEndian: address.sin_port)
        #expect(ProcessScanner.listeningPorts(pid: getpid()).contains(port))
    }
}
