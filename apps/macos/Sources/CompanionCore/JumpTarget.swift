import Foundation

/// One process in a session's ancestry, from the agent up toward launchd.
public struct ProcessNode: Equatable, Sendable {
    public var pid: Int32
    public var name: String
    /// Bundle id when this process is a running macOS app.
    public var bundleId: String?

    public init(pid: Int32, name: String, bundleId: String? = nil) {
        self.pid = pid
        self.name = name
        self.bundleId = bundleId
    }
}

/// The app a click on a session should bring forward. Agent-neutral: computed only
/// from the reported origin and the process tree, never from the agent id.
public struct JumpTarget: Equatable, Sendable {
    public var bundleId: String
    /// The specific app process, when known (matters if the app has several instances).
    public var appPID: Int32?

    public init(bundleId: String, appPID: Int32? = nil) {
        self.bundleId = bundleId
        self.appPID = appPID
    }

    /// Short label for tooltips/accessibility, e.g. "Ghostty", "T3 Code".
    public var appName: String {
        switch bundleId {
        case "com.apple.Terminal": "Terminal"
        case "com.googlecode.iterm2": "iTerm"
        case "com.mitchellh.ghostty": "Ghostty"
        case "net.kovidgoyal.kitty": "kitty"
        case "com.github.wez.wezterm": "WezTerm"
        case "dev.warp.Warp-Stable": "Warp"
        case "com.microsoft.VSCode": "VS Code"
        case "dev.zed.Zed": "Zed"
        case "com.t3tools.t3code": "T3 Code"
        default: bundleId.split(separator: ".").last.map(String.init) ?? bundleId
        }
    }
}

public enum JumpResolver {
    static let terminalPrograms: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "ghostty": "com.mitchellh.ghostty",
        "kitty": "net.kovidgoyal.kitty",
        "WezTerm": "com.github.wez.wezterm",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "vscode": "com.microsoft.VSCode",
    ]

    /// - Parameter ancestry: the agent process first, then its parents (empty if it exited).
    public static func resolve(origin: AgentSession.Origin?, ancestry: [ProcessNode]) -> JumpTarget? {
        // The nearest GUI app above the agent is ground truth for "which app hosts this".
        if let host = ancestry.first(where: { $0.bundleId != nil }), let id = host.bundleId {
            return JumpTarget(bundleId: id, appPID: host.pid)
        }
        // Otherwise use the reported environment: it survives broken process trees
        // (tmux reparents to launchd, `open -a`, double-forks).
        if let id = origin?.bundleId ?? origin?.termProgram.flatMap({ terminalPrograms[$0] }) {
            return JumpTarget(bundleId: id)
        }
        return nil
    }
}
