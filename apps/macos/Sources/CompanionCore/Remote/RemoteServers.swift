import Foundation

/// Processes listening on TCP ports on a remote machine, and their parents, as reported
/// by `RemoteScript` in an `N` frame. Fed to `DevServerScanner` like local processes.
struct RemoteServerFacts: Equatable {
    struct Process: Equatable {
        var entry: ProcessEntry
        var ports: [UInt16]
        var loopbackPorts: Set<UInt16>
        var executablePath: String?
        var snapshot: ProcessSnapshot
    }

    var processes: [Int32: Process] = [:]

    init() {}

    init(_ body: Data) {
        for line in String(decoding: body, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 8, let pid = Int32(fields[0]), let parent = Int32(fields[1]),
                  let start = TimeInterval(fields[2]) else { continue }
            let executable = fields[4].isEmpty ? nil : fields[4]
            let startedAt = Date(timeIntervalSince1970: start)
            var ports: [UInt16] = [], loopback = Set<UInt16>()
            for token in fields[3].split(separator: " ") {
                if token.hasPrefix("l"), let port = UInt16(token.dropFirst()) {
                    ports.append(port)
                    loopback.insert(port)
                } else if let port = UInt16(token) {
                    ports.append(port)
                }
            }
            let name = executable.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            processes[pid] = Process(
                entry: ProcessEntry(pid: pid, parentPID: parent, name: name, startedAt: startedAt),
                ports: Array(Set(ports)).sorted(), loopbackPorts: loopback, executablePath: executable,
                snapshot: ProcessSnapshot(pid: pid, name: name,
                                          arguments: fields[6].split(separator: "\u{1D}").map(String.init),
                                          environment: fields[7].isEmpty ? [:] : ["CLAUDE_CODE_SESSION_ID": fields[7]],
                                          cwd: fields[5].isEmpty ? nil : fields[5], startedAt: startedAt))
        }
    }

    /// - Parameter address: where this Mac reaches the machine; servers bound only to the
    ///   machine's loopback interface get no URL.
    func servers(host: String, address: String?, agentPIDs: Set<Int32>) -> [DevServer] {
        let processes = processes
        let loopbackOnly = Set(processes.values.flatMap(\.loopbackPorts)).subtracting(
            processes.values.flatMap { process in process.ports.filter { !process.loopbackPorts.contains($0) } })
        return DevServerScanner.servers(
            processes: processes.values.map(\.entry), agentPIDs: agentPIDs, ownPID: 0,
            listeningPorts: { processes[$0]?.ports ?? [] }, executablePath: { processes[$0]?.executablePath },
            snapshot: { processes[$0]?.snapshot }, isInRepository: { _ in false }
        ).map { server in
            var server = server
            server.id = "\(host):\(server.id)"
            server.remote = DevServer.Remote(host: host, address: server.ports.allSatisfy(loopbackOnly.contains) ? nil : address)
            return server
        }
    }
}
