import AppKit
import CompanionCore
import OSLog
import UserNotifications

@MainActor
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let log = Logger(subsystem: "com.ikramulhasan.AgentCompanion", category: "alerts")

    private var planner = AlertPlanner()
    private let center: UNUserNotificationCenter?
    private var authorization: Task<Bool, Never>?
    private let onOpen: (String) -> Void

    init(onOpen: @escaping (String) -> Void) {
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        self.onOpen = onOpen
        super.init()
        center?.delegate = self
    }

    func update(_ sessions: [AgentSession], settings: AlertSettings) {
        let actions = planner.update(sessions, settings: settings) { ProjectIcons.shared.project(for: $0).name }
        guard let center else { return }
        for action in actions {
            switch action {
            case .withdraw(let id):
                center.removePendingNotificationRequests(withIdentifiers: [id])
                center.removeDeliveredNotifications(withIdentifiers: [id])
            case .post(let alert):
                post(alert, center: center)
            }
        }
    }

    private func post(_ alert: SessionAlert, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let delay = alert.fireAt.timeIntervalSinceNow
        let trigger = delay >= 1 ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false) : nil
        let request = UNNotificationRequest(identifier: alert.sessionID, content: content, trigger: trigger)
        let authorization = authorization ?? Task {
            (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        self.authorization = authorization
        Task {
            guard await authorization.value else { return }
            do { try await center.add(request) } catch {
                Self.log.error("Notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        await MainActor.run { onOpen(id) }
    }
}
