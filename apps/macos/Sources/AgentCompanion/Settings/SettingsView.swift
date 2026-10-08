import CompanionCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: SessionStore
    let usage: UsageStore

    var body: some View {
        Form {
            Section {
                AgentsList(settings: settings, store: store, usage: usage, agents: agents)
            } header: {
                Text("Agents")
            } footer: {
                Text("Status shows running sessions in the panel. Usage shows session and weekly limits, "
                     + "reset times and cost, fetched through CodexBar every few minutes.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LoaderGallery(selection: $settings.loader.global)
            } header: {
                Text("Loading indicator")
            } footer: {
                Text("Shown while an agent is working. Agents without an override use this.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !agents.isEmpty {
                Section("Per agent") {
                    ForEach(agents, id: \.id) { agent in
                        AgentLoaderRow(agent: agent, settings: settings)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 640)
    }

    /// Agents the user added, then any that reported a session or have an override.
    private var agents: [AgentSession.AgentInfo] {
        var seen = Set<String>()
        let all = settings.agents.added.map { AgentSession.AgentInfo(id: $0, name: usage.name(for: $0) ?? $0) }
            + store.seenAgents
            + settings.loader.perAgent.keys.sorted().map { .init(id: $0, name: usage.name(for: $0) ?? $0) }
        return all.filter { seen.insert($0.id).inserted }
    }
}

/// The user's agent list with per-agent Status / Usage toggles and an Add menu fed by
/// CodexBar's provider catalog. Nothing is auto-detected.
private struct AgentsList: View {
    @Bindable var settings: AppSettings
    let store: SessionStore
    let usage: UsageStore
    let agents: [AgentSession.AgentInfo]

    var body: some View {
        if agents.isEmpty {
            Text("No agents added yet.")
                .foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("Agent")
                    Text("Status").gridColumnAlignment(.center)
                    Text("Usage").gridColumnAlignment(.center)
                    Color.clear.frame(width: 16, height: 1)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

                ForEach(agents, id: \.id) { agent in
                    GridRow {
                        HStack(spacing: 8) {
                            AgentGlyph(agentID: agent.id)
                            Text(agent.name)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Toggle("Show running status for \(agent.name)", isOn: Binding(
                            get: { settings.agents.showsStatus(agent.id) },
                            set: { settings.agents.setStatus($0, for: agent.id) }))
                            .labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)

                        Toggle("Show usage for \(agent.name)", isOn: Binding(
                            get: { settings.agents.showsUsage(agent.id) },
                            set: { settings.agents.setUsage($0, for: agent.id) }))
                            .labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)
                            .disabled(!usageAvailable(agent.id))
                            .help(usageAvailable(agent.id) ? "" : "CodexBar has no usage data for this agent")

                        Button {
                            settings.agents.remove(agent.id)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .opacity(settings.agents.added.contains(agent.id) ? 1 : 0)
                        .disabled(!settings.agents.added.contains(agent.id))
                        .help("Remove \(agent.name)")
                        .accessibilityLabel("Remove \(agent.name)")
                    }
                }
            }
        }

        HStack {
            AddAgentMenu(settings: settings, usage: usage)
            Spacer()
            switch usage.catalogState {
            case .loading:
                ProgressView().controlSize(.small)
            case .unavailable(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            case .loaded:
                Button("Refresh usage") { usage.refreshAll() }
                    .controlSize(.small)
                    .disabled(settings.agents.usage.isEmpty)
            }
        }
    }

    /// Usage needs a CodexBar provider with that id. Agents that only report sessions
    /// (e.g. a custom integration) can't have usage.
    private func usageAvailable(_ id: String) -> Bool {
        usage.catalogState != .loaded || usage.catalog.contains { $0.id == id }
    }
}

private struct AddAgentMenu: View {
    @Bindable var settings: AppSettings
    let usage: UsageStore
    @State private var showingPicker = false
    @State private var query = ""

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            Label("Add agent…", systemImage: "plus")
        }
        .disabled(usage.catalog.isEmpty)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search \(usage.catalog.count) providers", text: $query)
                    .textFieldStyle(.roundedBorder)
                List(available) { provider in
                    Button {
                        settings.agents.add(provider.id)
                        showingPicker = false
                        query = ""
                    } label: {
                        HStack(spacing: 8) {
                            AgentGlyph(agentID: provider.id)
                            Text(provider.name)
                            Spacer()
                            Text(provider.id).foregroundStyle(.tertiary).font(.system(size: 11))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .padding(12)
            .frame(width: 300, height: 360)
        }
    }

    private var available: [ProviderInfo] {
        let added = Set(settings.agents.added)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return usage.catalog.filter {
            !added.contains($0.id) && (q.isEmpty || $0.name.lowercased().contains(q) || $0.id.contains(q))
        }
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
