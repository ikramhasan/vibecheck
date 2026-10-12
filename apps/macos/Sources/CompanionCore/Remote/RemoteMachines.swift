import Observation

/// One `RemoteSessionSource` per host in Settings, registered with the session store.
@MainActor
@Observable
public final class RemoteMachines {
    public private(set) var sources: [RemoteSessionSource] = []
    @ObservationIgnored private let store: SessionStore

    public init(store: SessionStore) {
        self.store = store
    }

    public func update(_ hosts: [RemoteHost]) {
        for source in sources where !hosts.contains(source.host) { store.remove(source) }
        sources = hosts.map { host in
            if let existing = sources.first(where: { $0.host == host }) { return existing }
            let source = RemoteSessionSource(host: host)
            store.add(source)
            source.start()
            return source
        }
    }

    public var servers: [DevServer] { sources.flatMap(\.servers) }

    public func reconnect() {
        sources.forEach { $0.reconnect() }
    }

    public func source(for host: RemoteHost) -> RemoteSessionSource? {
        sources.first { $0.host == host }
    }

    public func git(on alias: String) -> GitReading? {
        sources.first { $0.host.alias == alias }.map(RemoteGit.init(source:))
    }
}
