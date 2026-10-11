import CompanionCore
import SwiftUI

/// Settings as a page inside the expanded edge panel. Sections cascade in from the
/// trailing side while the session list cascades out to the leading side.
struct SettingsPage: View {
    @Bindable var settings: AppSettings
    let store: SessionStore
    let usage: UsageStore
    /// The page is the one on screen (panel expanded and Settings selected).
    let isShown: Bool
    /// Page change (staggered hand-off) vs. panel expand/collapse.
    let paced: Bool
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .cascade(shown: isShown, index: 0, side: .trailing, paced: paced)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSection("Agents",
                                    footer: "Status shows running sessions in the panel. Usage shows session and "
                                        + "weekly limits, reset times and cost, fetched through CodexBar.") {
                        AgentsList(settings: settings, store: store, usage: usage, agents: agents)
                    }
                    .cascade(shown: isShown, index: 1, side: .trailing, paced: paced)

                    SettingsSection("Sessions",
                                    footer: "Finished sessions leave the panel after this long. They come back "
                                        + "when the agent starts working again.") {
                        HStack {
                            Text("Remove finished sessions")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer(minLength: 6)
                            Picker("Remove finished sessions", selection: $settings.finishedSessionRemoval) {
                                ForEach(FinishedSessionRemoval.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .fixedSize()
                        }
                        .frame(height: 30)
                    }
                    .cascade(shown: isShown, index: 2, side: .trailing, paced: paced)

                    SettingsSection("Loading indicator",
                                    footer: "Shown while an agent is working. Agents without an override use this.",
                                    grouped: false) {
                        LoaderGallery(selection: $settings.loader.global)
                    }
                    .cascade(shown: isShown, index: 3, side: .trailing, paced: paced)

                    if !agents.isEmpty {
                        SettingsSection("Per agent") {
                            VStack(spacing: 0) {
                                ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                                    if index > 0 { RowDivider() }
                                    AgentLoaderRow(agent: agent, settings: settings)
                                }
                            }
                        }
                        .cascade(shown: isShown, index: 4, side: .trailing, paced: paced)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            // Soft edges so scrolled content dissolves instead of being cut at the card edge.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 20)
                }
            }
        }
        .padding(.top, PanelMetrics.flare)
        .padding(.bottom, PanelMetrics.flare)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to agents")
            .accessibilityLabel("Back to agents")
            .keyboardShortcut(.cancelAction)

            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .frame(height: PanelMetrics.headerHeight)
        .padding(.leading, 10)
        .padding(.trailing, 16)
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

// MARK: - Section chrome

private struct SettingsSection<Content: View>: View {
    let title: String
    let footer: String?
    let grouped: Bool
    @ViewBuilder let content: Content

    init(_ title: String, footer: String? = nil, grouped: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.grouped = grouped
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            if grouped {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    )
            } else {
                content
            }

            if let footer {
                Text(footer)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
    }
}

// MARK: - Agents

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
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .frame(height: 30)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
                GridRow {
                    Text("Agent")
                    Text("Status").gridColumnAlignment(.center)
                    Text("Usage").gridColumnAlignment(.center)
                    Color.clear.frame(width: 14, height: 1)
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(height: 22)

                ForEach(agents, id: \.id) { agent in
                    GridRow {
                        HStack(spacing: 8) {
                            AgentGlyph(agentID: agent.id)
                            Text(agent.name)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Toggle("Show running status for \(agent.name)", isOn: Binding(
                            get: { settings.agents.showsStatus(agent.id) },
                            set: { settings.agents.setStatus($0, for: agent.id) }))
                            .labelsHidden()
                            .toggleStyle(.switch).controlSize(.mini)

                        Toggle("Show usage for \(agent.name)", isOn: Binding(
                            get: { settings.agents.showsUsage(agent.id) },
                            set: { settings.agents.setUsage($0, for: agent.id) }))
                            .labelsHidden()
                            .toggleStyle(.switch).controlSize(.mini)
                            .disabled(!usageAvailable(agent.id))
                            .help(usageAvailable(agent.id) ? "" : "CodexBar has no usage data for this agent")

                        Button {
                            settings.agents.remove(agent.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .opacity(settings.agents.added.contains(agent.id) ? 1 : 0)
                        .disabled(!settings.agents.added.contains(agent.id))
                        .help("Remove \(agent.name)")
                        .accessibilityLabel("Remove \(agent.name)")
                    }
                    .frame(height: 30)
                }
            }
        }

        RowDivider()
        HStack {
            AddAgentMenu(settings: settings, usage: usage)
            Spacer()
            switch usage.catalogState {
            case .loading:
                ProgressView().controlSize(.mini)
            case .unavailable(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(reason)
            case .loaded:
                Button("Refresh usage") { usage.refreshAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(settings.agents.usage.isEmpty ? 0.25 : 0.5))
                    .disabled(settings.agents.usage.isEmpty)
            }
        }
        .frame(height: 32)
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
                .font(.system(size: 12))
                .foregroundStyle(usage.catalog.isEmpty ? Color.white.opacity(0.3) : Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(usage.catalog.isEmpty)
        .popover(isPresented: $showingPicker, arrowEdge: .leading) {
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

// MARK: - Loaders

/// Tile grid of every loader in the library; click to choose.
private struct LoaderGallery: View {
    @Binding var selection: LoaderStyle

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(LoaderStyle.allCases, id: \.self) { style in
                LoaderTile(style: style, selected: style == selection) { selection = style }
            }
        }
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
                LoaderView(style: style, size: 22, color: .white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(style.displayName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(selected ? 0.95 : 0.6))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 7)
            }
            .frame(height: 68)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.09 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.07),
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
        HStack(spacing: 8) {
            AgentGlyph(agentID: agent.id)
            Text(agent.name)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 6)
            LoaderView(style: settings.loader.style(for: agent.id), size: 14)
            Picker("Loader for \(agent.name)", selection: choice) {
                Text("Global (\(settings.loader.global.displayName))").tag(LoaderStyle?.none)
                Divider()
                ForEach(LoaderStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(LoaderStyle?.some(style))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
        .frame(height: 32)
    }
}
