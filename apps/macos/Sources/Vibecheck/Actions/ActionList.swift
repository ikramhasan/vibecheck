import AppKit
import CompanionCore
import SwiftUI

enum ActionMetrics {
    static let line: CGFloat = 24
    static let detailLine: CGFloat = 16
    static let row: CGFloat = line + detailLine + 6
    static let newRow: CGFloat = 34
    static let listPadding: CGFloat = 8
    static let editorHeight: CGFloat = 360
    static let logHeight: CGFloat = 520

    static func listContentHeight(_ count: Int) -> CGFloat {
        (count == 0 ? PanelMetrics.emptyListHeight : CGFloat(count) * row) + newRow + listPadding
    }

    static func listHeight(_ count: Int) -> CGFloat {
        min(listContentHeight(count), PanelMetrics.maxListHeight)
    }

    static func pageHeight(_ count: Int) -> CGFloat {
        PanelMetrics.flare * 2 + PanelMetrics.handleHeight + PanelMetrics.headerHeight + listHeight(count) + 12
    }
}

struct ActionRowItem: Identifiable {
    let action: QuickAction
    let directory: String
    var id: ActionRunKey { ActionRunKey(actionID: action.id, directory: directory) }
    var isMain: Bool { directory == action.directory }

    @MainActor static func all(_ store: ActionStore) -> [ActionRowItem] {
        store.actions.flatMap { action in
            ([action.directory] + store.otherDirectories(of: action)).map { ActionRowItem(action: action, directory: $0) }
        }
    }
}

struct ActionList: View {
    let store: ActionStore
    let shown: Bool
    let side: HorizontalEdge
    let paced: Bool
    let onNew: () -> Void
    let onEdit: (QuickAction) -> Void
    let onShowLog: (ActionRunKey) -> Void

    var body: some View {
        let items = ActionRowItem.all(store)
        VStack(spacing: 0) {
            if store.actions.isEmpty {
                Text("No actions yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: PanelMetrics.emptyListHeight)
                    .cascade(shown: shown, index: 1, side: side, paced: paced)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let action = item.action, directory = item.directory
                ActionRow(item: item, project: ProjectIcons.shared.project(for: action.directory),
                          run: store.run(for: action, in: directory),
                          onRun: { store.run(action, in: directory) }, onStop: { store.stop(action, in: directory) },
                          onEdit: { onEdit(action) }, onDelete: { store.delete(action) },
                          onDismiss: { store.dismiss(action, in: directory) },
                          onShowLog: { onShowLog(item.id) })
                    .frame(height: ActionMetrics.row)
                    .cascade(shown: shown, index: index + 1, side: side, paced: paced)
            }
            NewActionRow(action: onNew)
                .frame(height: ActionMetrics.newRow)
                .cascade(shown: shown, index: items.count + 1, side: side, paced: paced)
        }
        .padding(.vertical, ActionMetrics.listPadding / 2)
        .padding(.horizontal, 6)
    }
}

private struct ActionRow: View {
    let item: ActionRowItem
    let project: ProjectInfo
    let run: ActionRun?
    let onRun: () -> Void
    let onStop: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void
    let onShowLog: () -> Void
    @State private var hovering = false
    @State private var confirmingDelete = false

    private var action: QuickAction { item.action }
    private var running: Bool { run?.isRunning == true }
    private var folderMissing: Bool { !running && !QuickAction.isDirectory(item.directory) }
    private var checkoutName: String {
        (ProjectIcons.shared.resolver.checkout(for: item.directory) as NSString).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProjectBadge(project: project, size: 18)
                Text(action.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                trailing
            }
            .frame(height: ActionMetrics.line)

            HStack(spacing: 5) {
                if folderMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text("Folder not found")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                } else if item.isMain {
                    Text(action.command)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(checkoutName)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.leading, 26)
            .frame(height: ActionMetrics.detailLine, alignment: .top)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .glassEffect(rowGlass, in: .rect(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) {
                hovering = h
                if !h { confirmingDelete = false }
            }
        }
        .onTapGesture(perform: primary)
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.isMain ? "\(action.name), \(statusText)" : "\(action.name) in \(checkoutName), \(statusText)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(running ? "Shows its output" : "Runs \(action.command)")
        .accessibilityAction(.default) { primary() }
        .accessibilityActions {
            if running { Button("Stop", action: onStop) }
            if run != nil { Button("Show output", action: onShowLog) }
            if item.isMain {
                Button("Edit", action: onEdit)
                Button("Delete", action: onDelete)
            } else if !running {
                Button("Dismiss", action: onDismiss)
            }
        }
    }

    private func primary() {
        if running { onShowLog() } else { onRun() }
    }

    private var rowGlass: Glass { hovering ? .regular.interactive() : .identity }

    @ViewBuilder private var trailing: some View {
        if hovering {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    if run != nil {
                        RowAction(systemImage: "text.alignleft", label: "Show output", action: onShowLog)
                    }
                    if item.isMain {
                        RowAction(systemImage: "pencil", label: "Edit", action: onEdit)
                        deleteButton
                    } else if !running {
                        RowAction(systemImage: "xmark", label: "Dismiss", action: onDismiss)
                    }
                    if running {
                        RowAction(systemImage: "stop.fill", label: "Stop", action: onStop)
                    } else {
                        RowAction(systemImage: "play.fill", label: "Run", action: onRun)
                    }
                }
            }
            .transition(.opacity)
        } else {
            status.transition(.opacity)
        }
    }

    @ViewBuilder private var deleteButton: some View {
        if confirmingDelete {
            Button {
                confirmingDelete = false
                onDelete()
            } label: {
                Text("Delete")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.red).interactive(), in: .capsule)
            .help("Click again to delete this action")
            .accessibilityLabel("Confirm delete")
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            RowAction(systemImage: "trash", label: "Delete") {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { confirmingDelete = true }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch run {
        case .running(let startedAt):
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(ElapsedFormat.short(since: startedAt, now: context.date))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        case .finished(let outcome, _):
            Button(action: onShowLog) {
                HStack(spacing: 4) {
                    Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(outcome.succeeded ? Color.green : outcome == .stopped ? .secondary : .red)
                    Text(outcome.summary)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show output")
        case nil:
            EmptyView()
        }
    }

    private var statusText: String {
        switch run {
        case .running: "running"
        case .finished(let outcome, _): outcome.summary
        case nil: folderMissing ? "folder not found" : "not run yet"
        }
    }

    private var tooltip: String {
        [action.command, ProjectPath.abbreviate(item.directory),
         running ? "Click to show output" : "Click to run"].joined(separator: "\n")
    }
}

private struct NewActionRow: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18)
                Text("New action")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundStyle(hovering ? HierarchicalShapeStyle.primary : .secondary)
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(hovering ? .regular.interactive() : .identity, in: .rect(cornerRadius: 12, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .padding(.vertical, 2)
    }
}
