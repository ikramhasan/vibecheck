import AppKit
import CompanionCore
import SwiftUI

/// Per-agent branding, sourced from CodexBar so every provider it knows has an icon.
/// Icons are CodexBar's `ProviderIcon-<id>.svg` (MIT, synced by
/// `scripts/sync-provider-icons.sh`), rendered as templates and tinted with the
/// provider's brand colour, the same way CodexBar's menu draws them.
/// Unknown agents get a generic terminal glyph, so adding one never *requires* UI work.
enum AgentAppearance {
    /// Providers that reuse another provider's icon (from CodexBar's descriptors).
    private static let iconAliases: [String: String] = [
        "openai": "codex",
        "azureopenai": "codex",
        "moonshot": "kimi",
        "alibabatokenplan": "alibaba",
    ]

    /// Brand colours from CodexBar's `ProviderBranding.color` (v0.73.0).
    private static let brandHex: [String: UInt32] = [
        "abacus": 0x814EE8,
        "aiand": 0xE25C2B,
        "aixy": 0x123650,
        "alibaba": 0xFF6A00,
        "alibabatokenplan": 0xFF6A00,
        "amp": 0xF34E3F,
        "antigravity": 0x60BA7E,
        "augment": 0x1AA049,
        "azureopenai": 0x0078D4,
        "bedrock": 0x01A88D,
        "bifrost": 0x33C09E,
        "chutes": 0x3184FF,
        "claude": 0xCC7C5E,
        "clawrouter": 0x596EF6,
        "clinepass": 0x5487C8,
        "codebuff": 0x00FF95,
        "coderabbit": 0xFF5C35,
        "codex": 0x49A3B0,
        "commandcode": 0x8C4EDD,
        "copilot": 0xA855F7,
        "cursor": 0xF54E00,
        "deepgram": 0x6467F2,
        "deepseek": 0x4D6BFE,
        "devin": 0x317CFF,
        "doubao": 0x3370FF,
        "factory": 0xFF6B35,
        "fireworks": 0xF25B1C,
        "gemini": 0xAB87EA,
        "grok": 0x10A37F,
        "groq": 0xF56844,
        "huggingface": 0xFFD21E,
        "ibmbob": 0x0E61FA,
        "jetbrains": 0xFF3399,
        "kilo": 0xF27027,
        "kimi": 0xFE603C,
        "kiro": 0x9046FF,
        "langdock": 0x5A4AE7,
        "litellm": 0x4C89F0,
        "lithosai": 0x6B7280,
        "llmman": 0x6CC5B0,
        "llmproxy": 0x24B47E,
        "longcat": 0x29E154,
        "mimo": 0xFF6900,
        "minimax": 0xFE603C,
        "mistral": 0xFF5229,
        "moonshot": 0x205DEB,
        "muse": 0x0668E1,
        "museai": 0x0668E1,
        "neuralwatt": 0xD55934,
        "notion": 0x337EA9,
        "nous": 0xD6A55C,
        "ollama": 0x888888,
        "openai": 0x0F826E,
        "opencode": 0x3B82F6,
        "opencodego": 0x3B82F6,
        "openrouter": 0x6467F2,
        "perplexity": 0x20B2AA,
        "pi": 0x7C3AED,
        "qoder": 0x10B981,
        "qwencloud": 0x615CED,
        "replicate": 0x000000,
        "sakana": 0x2975DB,
        "stepfun": 0x2196F2,
        "sub2api": 0x14B8A6,
        "synthetic": 0x141414,
        "t3chat": 0xF56647,
        "typesafe": 0x111111,
        "v0": 0x111111,
        "venice": 0x3C8FDD,
        "vertexai": 0x4285F4,
        "warp": 0x938BB4,
        "wayfinder": 0x10A37F,
        "windsurf": 0x34E8BB,
        "xai": 0x8E8E93,
        "zai": 0xE85A6A,
        "zed": 0x084EFF,
        "zoommate": 0x0B5CFF,
    ]

    static func tint(for id: String) -> Color {
        brandHex[id].map(brandColor) ?? .white.opacity(0.7)
    }

    static func brandColor(_ hex: UInt32) -> Color {
        let c = Color(red: Double((hex >> 16) & 0xFF) / 255,
                      green: Double((hex >> 8) & 0xFF) / 255,
                      blue: Double(hex & 0xFF) / 255)
        // Near-black brands (Replicate, TypeSafe, …) would vanish on the dark panel.
        let luminance = 0.2126 * Double((hex >> 16) & 0xFF) + 0.7152 * Double((hex >> 8) & 0xFF)
            + 0.0722 * Double(hex & 0xFF)
        return luminance < 60 ? .white.opacity(0.85) : c
    }

    /// SwiftPM's resource bundle: in `Contents/Resources` of the .app, or next to the
    /// binary under `swift run`. Resolved by hand because `Bundle.module` traps when absent.
    static let iconBundle: Bundle? = {
        let name = "Vibecheck_Vibecheck.bundle"
        let candidates = [Bundle.main.resourceURL, Bundle.main.executableURL?.deletingLastPathComponent()]
        return candidates.lazy.compactMap { $0?.appending(path: name) }.compactMap(Bundle.init(url:)).first
    }()

    @MainActor private static var cache: [String: NSImage] = [:]
    @MainActor private static var missing: Set<String> = []

    /// Template image for the agent, or nil when CodexBar has no icon for it.
    @MainActor static func icon(for id: String) -> NSImage? {
        if let image = cache[id] { return image }
        if missing.contains(id) { return nil }
        let name = "ProviderIcon-" + (iconAliases[id] ?? id)
        guard let url = iconBundle?.url(forResource: name, withExtension: "svg", subdirectory: "ProviderIcons"),
              let image = NSImage(contentsOf: url) else {
            missing.insert(id)
            return nil
        }
        // CodexBar's SVGs mix white, black and currentColor silhouettes; as a template
        // only the alpha matters, so they all tint consistently.
        image.isTemplate = true
        cache[id] = image
        return image
    }
}

struct AgentGlyph: View {
    let agentID: String
    var size: CGFloat = 13

    var body: some View {
        Group {
            if let icon = AgentAppearance.icon(for: agentID) {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: size * 0.75, weight: .semibold))
            }
        }
        .foregroundStyle(AgentAppearance.tint(for: agentID))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
