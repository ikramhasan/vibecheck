import CompanionCore
import SwiftUI

/// Optional per-agent branding. Agents not listed here still work and get the
/// generic look, so adding an agent never *requires* touching the UI.
struct AgentAppearance {
    enum Glyph {
        case symbol(String)
        case text(String)
    }

    var glyph: Glyph
    var tint: Color

    static let generic = AgentAppearance(glyph: .symbol("terminal"), tint: .white.opacity(0.7))

    private static let registry: [String: AgentAppearance] = [
        "pi": AgentAppearance(glyph: .text("π"), tint: Color(red: 0.55, green: 0.75, blue: 1.0)),
        "claude": AgentAppearance(glyph: .symbol("asterisk"), tint: Color(red: 0.85, green: 0.47, blue: 0.34)),
        "codex": AgentAppearance(glyph: .symbol("hexagon"), tint: .white.opacity(0.85)),
    ]

    static func forAgent(_ id: String) -> AgentAppearance { registry[id] ?? generic }

    /// Agents listed in Settings even before they have reported a session.
    static let knownAgents: [AgentSession.AgentInfo] = [
        .init(id: "pi", name: "pi"),
        .init(id: "claude", name: "Claude Code"),
        .init(id: "codex", name: "Codex"),
    ]
}

struct AgentGlyph: View {
    let agentID: String

    var body: some View {
        let appearance = AgentAppearance.forAgent(agentID)
        Group {
            switch appearance.glyph {
            case .symbol(let name):
                Image(systemName: name).font(.system(size: 10, weight: .semibold))
            case .text(let text):
                Text(text).font(.system(size: 12, weight: .bold, design: .serif))
            }
        }
        .foregroundStyle(appearance.tint)
        .frame(width: 12)
        .accessibilityHidden(true)
    }
}
