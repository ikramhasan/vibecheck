import CompanionCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: SessionStore

    var body: some View {
        Form {
            Section {
                LoaderGallery(selection: $settings.loader.global)
            } header: {
                Text("Loading indicator")
            } footer: {
                Text("Shown while an agent is working. Agents without an override use this.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Per agent") {
                ForEach(agents, id: \.id) { agent in
                    AgentLoaderRow(agent: agent, settings: settings)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 560)
    }

    /// Known agents, plus anything currently running or already overridden.
    private var agents: [AgentSession.AgentInfo] {
        var seen = Set<String>()
        let all = AgentAppearance.knownAgents
            + store.sessions.map(\.agent)
            + settings.loader.perAgent.keys.sorted().map { .init(id: $0, name: $0) }
        return all.filter { seen.insert($0.id).inserted }
    }
}

/// Tile grid of every loader in the library; click to choose.
private struct LoaderGallery: View {
    @Binding var selection: LoaderStyle

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(LoaderStyle.allCases, id: \.self) { style in
                LoaderTile(style: style, selected: style == selection) { selection = style }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LoaderTile: View {
    let style: LoaderStyle
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                LoaderView(style: style, size: 28, color: .white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(style.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(selected ? 0.95 : 0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
            .frame(height: 96)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: hovering ? 0.12 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.08),
                                  lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .accessibilityLabel(style.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AgentLoaderRow: View {
    let agent: AgentSession.AgentInfo
    @Bindable var settings: AppSettings

    var body: some View {
        // nil = follow the global style.
        let choice = Binding<LoaderStyle?>(
            get: { settings.loader.perAgent[agent.id] },
            set: { settings.loader.setOverride($0, for: agent.id) }
        )
        HStack(spacing: 10) {
            AgentGlyph(agentID: agent.id)
            Picker(agent.name, selection: choice) {
                Text("Global (\(settings.loader.global.displayName))").tag(LoaderStyle?.none)
                Divider()
                ForEach(LoaderStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(LoaderStyle?.some(style))
                }
            }
            LoaderView(style: settings.loader.style(for: agent.id), size: 16)
                .frame(width: 20)
        }
    }
}
