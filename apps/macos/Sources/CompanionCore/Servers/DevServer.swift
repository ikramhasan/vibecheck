import Foundation

public struct DevServer: Identifiable, Equatable, Sendable {
    public enum Framework: String, CaseIterable, Sendable {
        case nextjs, nuxt, astro, storybook, vite, wrangler
        case django, flask, fastapi, rails
        case node, bun, deno, python, ruby, php
        case docker
        case app

        public var displayName: String {
            switch self {
            case .nextjs: "Next.js"
            case .nuxt: "Nuxt"
            case .astro: "Astro"
            case .storybook: "Storybook"
            case .vite: "Vite"
            case .wrangler: "Wrangler"
            case .django: "Django"
            case .flask: "Flask"
            case .fastapi: "FastAPI"
            case .rails: "Rails"
            case .node: "Node.js"
            case .bun: "Bun"
            case .deno: "Deno"
            case .python: "Python"
            case .ruby: "Ruby"
            case .php: "PHP"
            case .docker: "Docker"
            case .app: "App"
            }
        }
    }

    public var id: String
    public var framework: Framework
    public var pid: Int32
    public var startedAt: Date
    public var ports: [UInt16]
    public var cwd: String?
    public var ancestorPIDs: [Int32]
    public var claudeSessionID: String?
    public var appPath: String?
    public var hostsAgent: Bool
    public var remote: Remote?

    /// A server on another machine: its ssh host, and the address this Mac reaches it at
    /// (`nil` when it only listens on that machine's loopback interface).
    public struct Remote: Equatable, Sendable {
        public var host: String
        public var address: String?

        public init(host: String, address: String?) {
            self.host = host
            self.address = address
        }
    }

    public init(id: String, framework: Framework, pid: Int32, startedAt: Date, ports: [UInt16], cwd: String? = nil,
                ancestorPIDs: [Int32] = [], claudeSessionID: String? = nil, appPath: String? = nil,
                hostsAgent: Bool = false) {
        self.id = id
        self.framework = framework
        self.pid = pid
        self.startedAt = startedAt
        self.ports = ports
        self.cwd = cwd
        self.ancestorPIDs = ancestorPIDs
        self.claudeSessionID = claudeSessionID
        self.appPath = appPath
        self.hostsAgent = hostsAgent
    }

    public var name: String {
        appPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? framework.displayName
    }

    public var port: UInt16? { ports.first }
    public var address: String? { port.map { "\(remote?.host ?? "localhost"):\($0)" } }
    public var url: URL? {
        guard let port else { return nil }
        guard let remote else { return URL(string: "http://localhost:\(port)") }
        return remote.address.flatMap { URL(string: "http://\($0.contains(":") ? "[\($0)]" : $0):\(port)") }
    }
    public var summary: String { address.map { "\(name) on \($0)" } ?? name }
    public var canStop: Bool { framework != .docker && !hostsAgent && remote == nil }

    public func wasStarted(by session: AgentSession) -> Bool {
        guard remote?.host == session.host else { return false }
        if let claudeSessionID {
            return session.agent.id == AgentIdentity.claude.id && session.sessionID == claudeSessionID
        }
        return session.pid.map(ancestorPIDs.contains) ?? false
    }
}
