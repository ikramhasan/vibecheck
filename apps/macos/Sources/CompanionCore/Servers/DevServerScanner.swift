import Darwin
import Foundation

public enum DevServerScanner {
    static let firstEphemeralPort: UInt16 = 49152

    public static func scan(agentPIDs: Set<Int32>) -> [DevServer] {
        servers(processes: ProcessScanner.userProcesses(), agentPIDs: agentPIDs,
                listeningPorts: ProcessScanner.listeningPorts(pid:),
                executablePath: ProcessScanner.executablePath(pid:),
                snapshot: ProcessScanner.snapshot(pid:), isInRepository: isInRepository)
    }

    static func servers(processes: [ProcessEntry], agentPIDs: Set<Int32>, ownPID: Int32 = getpid(),
                        listeningPorts: (Int32) -> [UInt16], executablePath: (Int32) -> String?,
                        snapshot: (Int32) -> ProcessSnapshot?, isInRepository: (String) -> Bool) -> [DevServer] {
        let table = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let excluded = agentPIDs.union([ownPID])
        func isServerProcess(_ process: ProcessEntry) -> Bool {
            !excluded.contains(process.pid) && runtime(process.name) != nil
                && !isBundled(executablePath(process.pid))
        }

        var docker: [DevServer] = []
        var portsByRoot: [Int32: Set<UInt16>] = [:]
        var membersByRoot: [Int32: Set<Int32>] = [:]
        for process in processes where !excluded.contains(process.pid) {
            guard let runtime = runtime(process.name) else { continue }
            let ports = listeningPorts(process.pid).filter { $0 < firstEphemeralPort }
            guard !ports.isEmpty else { continue }
            if runtime == .docker {
                docker += ports.map {
                    DevServer(id: "docker:\($0)", framework: .docker, pid: process.pid,
                              startedAt: process.startedAt, ports: [$0])
                }
                continue
            }
            guard isServerProcess(process) else { continue }
            var chain = [process]
            while let parent = table[chain.last!.parentPID], parent.pid > 1, isServerProcess(parent) {
                chain.append(parent)
            }
            let root = chain.last!.pid
            if let launcher = table[chain.last!.parentPID], isBundled(executablePath(launcher.pid)) { continue }
            portsByRoot[root, default: []].formUnion(ports)
            membersByRoot[root, default: []].formUnion(chain.map(\.pid))
        }

        let trees = portsByRoot.compactMap { root, ports -> DevServer? in
            guard let entry = table[root] else { return nil }
            let rootSnapshot = snapshot(root)
            let arguments = membersByRoot[root, default: []].compactMap { snapshot($0)?.arguments }
            return DevServer(id: "\(root)", framework: framework(arguments: arguments) ?? runtime(entry.name)!,
                             pid: root, startedAt: entry.startedAt, ports: ports.sorted(), cwd: rootSnapshot?.cwd,
                             ancestorPIDs: ancestors(of: entry, in: table),
                             claudeSessionID: rootSnapshot?.environment["CLAUDE_CODE_SESSION_ID"])
        }
        let apps = projectApps(processes: processes, table: table, agentPIDs: agentPIDs,
                               executablePath: executablePath, snapshot: snapshot, isInRepository: isInRepository)
        return (trees + docker).sorted { ($0.port ?? 0, $0.id) < ($1.port ?? 0, $1.id) }
            + apps.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }

    private static func projectApps(processes: [ProcessEntry], table: [Int32: ProcessEntry], agentPIDs: Set<Int32>,
                                    executablePath: (Int32) -> String?, snapshot: (Int32) -> ProcessSnapshot?,
                                    isInRepository: (String) -> Bool) -> [DevServer] {
        let agentAncestors = Set(agentPIDs.compactMap { table[$0] }.flatMap { ancestors(of: $0, in: table) })
        return processes.compactMap { process in
            guard let path = executablePath(process.pid), let bundle = appBundle(mainExecutable: path),
                  isInRepository(bundle) else { return nil }
            let environment = snapshot(process.pid)?.environment
            return DevServer(id: "app:\(process.pid)", framework: .app, pid: process.pid, startedAt: process.startedAt,
                             ports: [], cwd: (bundle as NSString).deletingLastPathComponent,
                             ancestorPIDs: ancestors(of: process, in: table),
                             claudeSessionID: environment?["CLAUDE_CODE_SESSION_ID"], appPath: bundle,
                             hostsAgent: agentPIDs.contains(process.pid) || agentAncestors.contains(process.pid))
        }
    }

    static func appBundle(mainExecutable path: String) -> String? {
        guard let range = path.range(of: ".app/Contents/MacOS/"),
              !path[range.upperBound...].contains("/") else { return nil }
        let bundle = String(path[..<range.lowerBound]) + ".app"
        return bundle.dropLast(4).contains(".app/") ? nil : bundle
    }

    static func isInRepository(_ path: String) -> Bool {
        var directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appending(path: ".git").path) { return true }
            directory.deleteLastPathComponent()
        }
        return false
    }

    static func runtime(_ processName: String) -> DevServer.Framework? {
        let name = processName.lowercased()
        switch name {
        case "node": return .node
        case "bun": return .bun
        case "deno": return .deno
        case "workerd": return .wrangler
        default: break
        }
        if name.hasPrefix("python") { return .python }
        if name.hasPrefix("ruby") { return .ruby }
        if name.hasPrefix("php") { return .php }
        if name.hasPrefix("com.docker") { return .docker }
        return nil
    }

    static func isBundled(_ executablePath: String?) -> Bool {
        guard let executablePath else { return false }
        return executablePath.contains(".app/") && !executablePath.contains("/Python.app/")
    }

    private static let frameworkTokens: [(DevServer.Framework, Set<String>)] = [
        (.storybook, ["storybook", "@storybook", "start-storybook"]),
        (.nuxt, ["nuxt", "nuxi", "@nuxt"]),
        (.astro, ["astro"]),
        (.nextjs, ["next", "next-server"]),
        (.wrangler, ["wrangler", "workerd"]),
        (.vite, ["vite"]),
        (.django, ["runserver", "django-admin"]),
        (.flask, ["flask"]),
        (.fastapi, ["fastapi", "uvicorn"]),
        (.rails, ["rails", "puma"]),
    ]

    static func framework(arguments: [[String]]) -> DevServer.Framework? {
        let tokens = Set(arguments.joined().flatMap {
            $0.lowercased().split(whereSeparator: { $0 == "/" || $0 == " " }).map(String.init)
        })
        return frameworkTokens.first { !$0.1.isDisjoint(with: tokens) }?.0
    }

    private static func ancestors(of entry: ProcessEntry, in table: [Int32: ProcessEntry]) -> [Int32] {
        var pids: [Int32] = []
        var current = entry
        while let parent = table[current.parentPID], !pids.contains(parent.pid) {
            pids.append(parent.pid)
            current = parent
        }
        return pids
    }
}

public enum DevServerStopper {
    static let killDelay: Duration = .seconds(3)
    static let agentProcessNames: Set<String> = [CodexDiscovery.processName, "claude"]

    public static func stop(_ server: DevServer, agentPIDs: Set<Int32>) async {
        let targets = targets(of: server, processes: ProcessScanner.userProcesses(), agentPIDs: agentPIDs)
        for target in targets { kill(target.pid, SIGTERM) }
        try? await Task.sleep(for: killDelay)
        for target in targets where ProcessScanner.entry(pid: target.pid)?.startedAt == target.startedAt {
            kill(target.pid, SIGKILL)
        }
    }

    static func targets(of server: DevServer, processes: [ProcessEntry], agentPIDs: Set<Int32>,
                        ownPID: Int32 = getpid()) -> [ProcessEntry] {
        let protected = agentPIDs.union([ownPID, 0, 1])
        func isProtected(_ process: ProcessEntry) -> Bool {
            protected.contains(process.pid) || agentProcessNames.contains(process.name)
        }
        guard server.canStop,
              let root = processes.first(where: { $0.pid == server.pid && $0.startedAt == server.startedAt }),
              !isProtected(root)
        else { return [] }
        let children = Dictionary(grouping: processes, by: \.parentPID)
        var tree = [root]
        var index = 0
        while index < tree.count {
            tree += children[tree[index].pid, default: []].filter { child in
                !isProtected(child) && !tree.contains { $0.pid == child.pid }
            }
            index += 1
        }
        return tree
    }
}
