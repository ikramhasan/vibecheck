import AppKit
import CompanionCore
import SwiftUI

struct SubPageHeader<Trailing: View>: View {
    let title: String
    let backLabel: String
    let onBack: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .help(backLabel)
            .accessibilityLabel(backLabel)
            .keyboardShortcut(.cancelAction)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            trailing
        }
        .frame(height: PanelMetrics.headerHeight)
        .padding(.leading, 12)
        .padding(.trailing, 16)
    }
}

struct ActionEditorPage: View {
    let editing: QuickAction?
    let projects: [ProjectInfo]
    let isShown: Bool
    let paced: Bool
    let onSave: (QuickAction) -> Void
    let onClose: () -> Void
    @State private var draft = QuickAction()
    @FocusState private var nameFocused: Bool

    private var isNew: Bool { editing.map { $0.name.isEmpty } ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SubPageHeader(title: isNew ? "New action" : "Edit action", backLabel: "Back to actions",
                          onBack: onClose) { EmptyView() }
                .cascade(shown: isShown, index: 0, side: .trailing, paced: paced)

            VStack(alignment: .leading, spacing: 14) {
                field("Name") {
                    TextField("Start dev server", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                }
                .cascade(shown: isShown, index: 1, side: .trailing, paced: paced)

                field("Command") {
                    TextField("npm run dev", text: $draft.command, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(3...5)
                }
                .cascade(shown: isShown, index: 2, side: .trailing, paced: paced)

                field("Folder") { folderPicker }
                    .cascade(shown: isShown, index: 3, side: .trailing, paced: paced)

                Text("Actions belong to the project: a session's button runs them in that session's worktree. "
                     + "They run with your shell's environment but without a terminal, so commands that ask "
                     + "for input will fail.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .cascade(shown: isShown, index: 4, side: .trailing, paced: paced)

                HStack {
                    Spacer()
                    Button("Cancel", action: onClose)
                        .buttonStyle(.glass)
                    Button("Save") { onSave(draft.trimmed) }
                        .buttonStyle(.glassProminent)
                        .disabled(!draft.isComplete)
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.regular)
                .cascade(shown: isShown, index: 5, side: .trailing, paced: paced)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.top, PanelMetrics.flare)
        .padding(.bottom, PanelMetrics.flare)
        .onChange(of: editing, initial: true) { _, editing in
            draft = editing ?? QuickAction()
            if editing != nil { nameFocused = isNew }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isNew ? "New action" : "Edit action")
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var folderPicker: some View {
        HStack(spacing: 6) {
            Text(draft.directory.isEmpty ? "No folder chosen" : ProjectPath.abbreviate(draft.directory))
                .font(.system(size: 12))
                .foregroundStyle(draft.directory.isEmpty ? .tertiary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(draft.directory)
            if !projects.isEmpty {
                Menu("Projects") {
                    ForEach(projects, id: \.root) { project in
                        Button(project.name) { draft.directory = project.root }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .fixedSize()
                .help("Use a project with a running session")
            }
            Button("Choose…", action: chooseFolder)
                .buttonStyle(.glass)
        }
        .controlSize(.small)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if !draft.directory.isEmpty { panel.directoryURL = URL(fileURLWithPath: draft.directory) }
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            draft.directory = ProjectIcons.shared.resolver.mainCheckoutPath(for: url.path)
        }
    }
}

private extension QuickAction {
    var trimmed: QuickAction {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}

struct ActionLogPage: View {
    let store: ActionStore
    let runKey: ActionRunKey?
    let isShown: Bool
    let paced: Bool
    let onBack: () -> Void
    @State private var copied = false

    private var action: QuickAction? { runKey.flatMap { store.action($0.actionID) } }
    private var directory: String? { runKey?.directory }
    private var run: ActionRun? { action.flatMap { store.run(for: $0, in: directory) } }
    private var title: String {
        guard let action, let directory, directory != action.directory else { return action?.name ?? "Output" }
        return "\(action.name) · \((ProjectIcons.shared.resolver.checkout(for: directory) as NSString).lastPathComponent)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SubPageHeader(title: title, backLabel: "Back to actions", onBack: onBack) {
                if let action {
                    GlassEffectContainer(spacing: 4) {
                        HStack(spacing: 4) {
                            RowAction(systemImage: copied ? "checkmark" : "doc.on.doc", label: "Copy output") {
                                copy(store.log(for: action, in: directory))
                            }
                            if run?.isRunning == true {
                                RowAction(systemImage: "stop.fill", label: "Stop") { store.stop(action, in: directory) }
                            } else {
                                RowAction(systemImage: "play.fill", label: "Run again") { store.run(action, in: directory) }
                            }
                        }
                    }
                }
            }
            .cascade(shown: isShown, index: 0, side: .trailing, paced: paced)

            statusLine
                .padding(.horizontal, 16)
                .frame(height: 22, alignment: .top)
                .cascade(shown: isShown, index: 1, side: .trailing, paced: paced)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                output(action.map { store.log(for: $0, in: directory) } ?? "")
            }
            .padding(.horizontal, 10)
            .cascade(shown: isShown, index: 2, side: .trailing, paced: paced)
        }
        .padding(.top, PanelMetrics.flare)
        .padding(.bottom, PanelMetrics.flare)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Output of \(action?.name ?? "action")")
    }

    @ViewBuilder private var statusLine: some View {
        switch run {
        case .running(let startedAt):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Running for \(ElapsedFormat.short(since: startedAt, now: context.date))")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        case .finished(let outcome, let endedAt):
            Text("\(outcome.summary) · \(endedAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 11))
                .foregroundStyle(outcome.succeeded ? Color.green : outcome == .stopped ? .secondary : .red)
        case nil:
            EmptyView()
        }
    }

    private func output(_ text: String) -> some View {
        ScrollView(.vertical) {
            Text(text.isEmpty ? "No output" : text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .defaultScrollAnchor(.top, for: .alignment)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollIndicators(.automatic)
        .background(.quinary, in: .rect(cornerRadius: 10, style: .continuous))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeOut(duration: 0.12)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.12)) { copied = false }
        }
    }
}
