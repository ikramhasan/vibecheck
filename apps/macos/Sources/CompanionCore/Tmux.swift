import Foundation

public enum Tmux {
    public static let paneFormat = "#{pane_tty}\t#{session_name}\t#{window_id}\t#{pane_id}"
    public static let clientFormat = "#{client_tty}\t#{client_session}\t#{client_activity}\t#{client_pid}"

    public struct Pane: Equatable, Sendable {
        public var session: String
        public var window: String
        public var pane: String
    }

    public struct Client: Equatable, Sendable {
        public var tty: String
        public var session: String
        public var activity: Int
        public var pid: Int32
    }

    public static func socketPath(fromEnvironment value: String?) -> String? {
        guard let first = value?.split(separator: ",").first, !first.isEmpty else { return nil }
        return String(first)
    }

    public static func serverPID(fromEnvironment value: String?) -> Int32? {
        guard let parts = value?.split(separator: ","), parts.count > 1 else { return nil }
        return Int32(parts[1])
    }

    public static func pane(forTTY tty: String, in listing: String) -> Pane? {
        rows(listing).first { $0.count == 4 && $0[0] == tty }.map { Pane(session: $0[1], window: $0[2], pane: $0[3]) }
    }

    public static func bestClient(for session: String, in listing: String) -> Client? {
        let clients = rows(listing).compactMap { row -> Client? in
            guard row.count == 4, let pid = Int32(row[3]) else { return nil }
            return Client(tty: row[0], session: row[1], activity: Int(row[2]) ?? 0, pid: pid)
        }
        let attached = clients.filter { $0.session == session }
        return (attached.isEmpty ? clients : attached).max { $0.activity < $1.activity }
    }

    private static func rows(_ listing: String) -> [[String]] {
        listing.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }
}
