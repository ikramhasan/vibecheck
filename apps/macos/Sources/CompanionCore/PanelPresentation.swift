import Foundation

/// Pure decision logic for how the edge panel presents itself. Kept free of
/// AppKit/SwiftUI so it's unit-testable.
///
/// - No sessions (and no usage to show) → hidden.
/// - Sessions running → small collapsed tab.
/// - Hovered → expanded.
/// - A session newly needs attention → expanded on its own and stays open until
///   the user has seen it (hovered in, then out) or the request is resolved.
///   A *new* request re-opens it even if an earlier one was dismissed.
public struct PanelPresentation: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case hidden, collapsed, expanded }

    public private(set) var mode: Mode = .hidden
    public private(set) var acknowledged: Set<String> = []
    private var attentionKeys: Set<String> = []
    private var sessionCount = 0
    private var hovering = false
    /// Usage stats are enabled, so the tab stays reachable with no sessions running.
    private var hasPersistentContent = false

    public init() {}

    /// Attention requests the user hasn't seen yet.
    public var pendingAttention: Set<String> { attentionKeys.subtracting(acknowledged) }

    public mutating func update(sessions: [AgentSession]) {
        sessionCount = sessions.count
        attentionKeys = Set(sessions.compactMap(\.attentionKey))
        // Forget resolved requests so the same request later counts as new.
        acknowledged.formIntersection(attentionKeys)
        recompute()
    }

    public mutating func setPersistentContent(_ value: Bool) {
        guard value != hasPersistentContent else { return }
        hasPersistentContent = value
        recompute()
    }

    public mutating func setHovering(_ value: Bool) {
        guard value != hovering else { return }
        hovering = value
        if !value {
            // Pointer left the open panel: the user has seen what's there.
            acknowledged.formUnion(attentionKeys)
        }
        recompute()
    }

    private mutating func recompute() {
        if sessionCount == 0 && !hasPersistentContent {
            mode = .hidden
            hovering = false
        } else if hovering || !pendingAttention.isEmpty {
            mode = .expanded
        } else {
            mode = .collapsed
        }
    }
}
