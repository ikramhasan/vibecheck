import AppKit
import CompanionCore
import SwiftUI

enum FrameworkAppearance {
    private static let brandHex: [DevServer.Framework: UInt32] = [
        .nextjs: 0x000000,
        .nuxt: 0x00DC82,
        .astro: 0xBC52EE,
        .storybook: 0xFF4785,
        .vite: 0x9135FF,
        .wrangler: 0xF38020,
        .django: 0x44B78B,
        .flask: 0x3BABC3,
        .fastapi: 0x009688,
        .rails: 0xD30001,
        .node: 0x5FA04E,
        .bun: 0xFBF0DF,
        .deno: 0x000000,
        .python: 0x3776AB,
        .ruby: 0xCC342D,
        .php: 0x777BB4,
        .docker: 0x2496ED,
    ]

    static func tint(for framework: DevServer.Framework) -> Color {
        AgentAppearance.brandColor(brandHex[framework] ?? 0xFFFFFF)
    }

    @MainActor private static var cache: [DevServer.Framework: NSImage] = [:]

    @MainActor static func icon(for framework: DevServer.Framework) -> NSImage? {
        if let image = cache[framework] { return image }
        guard let url = AgentAppearance.iconBundle?.url(forResource: framework.rawValue, withExtension: "svg",
                                                         subdirectory: "FrameworkIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache[framework] = image
        return image
    }
}

struct FrameworkGlyph: View {
    let framework: DevServer.Framework
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let icon = FrameworkAppearance.icon(for: framework) {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "server.rack")
                    .font(.system(size: size * 0.75, weight: .semibold))
            }
        }
        .foregroundStyle(FrameworkAppearance.tint(for: framework))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ServerIcon: View {
    let server: DevServer
    var size: CGFloat = 14

    var body: some View {
        if let appPath = server.appPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                .resizable()
                .interpolation(.high)
                .frame(width: size + 2, height: size + 2)
                .accessibilityHidden(true)
        } else {
            FrameworkGlyph(framework: server.framework, size: size)
        }
    }
}
