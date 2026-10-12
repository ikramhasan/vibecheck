import Foundation

/// An ssh client process on this Mac, as candidates for carrying a remote session.
public struct LocalSSHClient: Equatable, Sendable {
    public var pid: Int32
    public var arguments: [String]
    public var tty: String?
    public var connections: [TCPConnection]

    public init(pid: Int32, arguments: [String], tty: String?, connections: [TCPConnection]) {
        self.pid = pid
        self.arguments = arguments
        self.tty = tty
        self.connections = connections
    }
}

/// Finds the local ssh process a remote agent is used through, so a click on the
/// session opens the app on this Mac that started it.
enum RemoteJump {
    /// - Parameter hostAddress: the remote address of vibecheck's own connection to that machine.
    static func sshPID(for link: RemoteLink, hostAddress: String, clients: [LocalSSHClient]) -> Int32? {
        let sameHost = clients.filter { $0.connections.contains { $0.remoteAddress == hostAddress } }
        if let forwarding = sameHost.first(where: { !link.listeningPorts.isDisjoint(with: forwardedPorts($0.arguments)) }) {
            return forwarding.pid
        }
        if let clientPort = link.clientPort, let serverPort = link.serverPort,
           let carrier = sameHost.first(where: { $0.connections.contains { $0.localPort == clientPort && $0.remotePort == serverPort } }) {
            return carrier.pid
        }
        let interactive = sameHost.filter { $0.tty != nil }
        return interactive.count == 1 ? interactive[0].pid : nil
    }

    /// Remote loopback ports forwarded with `-L [bind:]port:host:hostport`.
    static func forwardedPorts(_ arguments: [String]) -> Set<UInt16> {
        var specs: [String] = []
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            if argument == "-L", let spec = iterator.next() {
                specs.append(spec)
            } else if argument.hasPrefix("-L"), argument.count > 2 {
                specs.append(String(argument.dropFirst(2)))
            }
        }
        return Set(specs.compactMap { spec -> UInt16? in
            guard let portSeparator = spec.lastIndex(of: ":"), let port = UInt16(spec[spec.index(after: portSeparator)...])
            else { return nil }
            let rest = spec[..<portSeparator]
            let host = rest.hasSuffix("]")
                ? rest.lastIndex(of: "[").map { rest[rest.index(after: $0)..<rest.index(before: rest.endIndex)] }
                : rest.split(separator: ":", omittingEmptySubsequences: false).last
            guard let host, rest.contains(":") || rest.hasSuffix("]") else { return nil }
            return ["127.0.0.1", "localhost", "::1"].contains(String(host)) ? port : nil
        })
    }
}
