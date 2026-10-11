import Foundation

public enum SettleDelay {
    public static let quiet: TimeInterval = 0.3
    public static let maxWait: TimeInterval = 1.0
}

struct SettleSchedule: Equatable {
    private var firstChangeAt: Date?

    mutating func changed(at now: Date) -> Date {
        let first = firstChangeAt ?? now
        firstChangeAt = first
        return min(now.addingTimeInterval(SettleDelay.quiet), first.addingTimeInterval(SettleDelay.maxWait))
    }

    mutating func fired() {
        firstChangeAt = nil
    }
}

@MainActor
final class SettleTimer {
    private var schedule = SettleSchedule()
    private var pending: DispatchWorkItem?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func changed() {
        let now = Date.now
        let fireAt = schedule.changed(at: now)
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fire() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, fireAt.timeIntervalSince(now)), execute: item)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        schedule.fired()
    }

    private func fire() {
        pending = nil
        schedule.fired()
        action()
    }
}
