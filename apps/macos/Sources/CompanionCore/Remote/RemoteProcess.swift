import Foundation

/// How a remote agent reaches this Mac, as seen from the remote side.
struct RemoteLink: Equatable, Sendable {
    /// From `SSH_CONNECTION` of the agent or its nearest ancestor that has one.
    var clientPort: UInt16?
    var serverPort: UInt16?
    /// TCP ports the agent or its ancestors listen on, e.g. an app server reached through `ssh -L`.
    var listeningPorts: Set<UInt16> = []
}

/// One agent process on the remote, as reported by `RemoteScript` in a `P` frame.
struct RemoteProcess: Equatable {
    var snapshot: ProcessSnapshot
    var openFiles: [String]
    var link: RemoteLink

    init?(pid: Int32, body: Data) {
        var fields: [String: String] = [:]
        for line in String(decoding: body, as: UTF8.self).split(separator: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            fields[String(line[..<equals])] = String(line[line.index(after: equals)...])
        }
        guard let comm = fields["comm"], let start = fields["start"].flatMap(TimeInterval.init) else { return nil }
        let separator: Character = "\u{1F}"
        var environment: [String: String] = [:]
        if let entry = fields["env"], let equals = entry.firstIndex(of: "=") {
            environment[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
        let isNode = comm == "pi" || comm.hasPrefix(PiDiscovery.processName)
        snapshot = ProcessSnapshot(pid: pid, name: isNode ? PiDiscovery.processName : comm,
                                   arguments: (fields["args"] ?? "").split(separator: separator).map(String.init),
                                   environment: environment, cwd: fields["cwd"].flatMap { $0.isEmpty ? nil : $0 },
                                   startedAt: Date(timeIntervalSince1970: start))
        openFiles = (fields["files"] ?? "").split(separator: separator).map(String.init)
        let ssh = (fields["ssh"] ?? "").split(separator: " ")
        link = RemoteLink(clientPort: ssh.count == 4 ? UInt16(ssh[1]) : nil,
                          serverPort: ssh.count == 4 ? UInt16(ssh[3]) : nil,
                          listeningPorts: Set((fields["ports"] ?? "").split(separator: " ").compactMap { UInt16($0) }))
    }

    static func piFiles(_ listing: Data) -> [PiDiscovery.SessionFile] {
        String(decoding: listing, as: UTF8.self).split(separator: "\n").compactMap { line in
            guard let space = line.firstIndex(of: " "), let modified = TimeInterval(line[..<space]) else { return nil }
            return PiDiscovery.SessionFile(url: URL(fileURLWithPath: String(line[line.index(after: space)...])),
                                           modifiedAt: Date(timeIntervalSince1970: modified))
        }
    }
}
