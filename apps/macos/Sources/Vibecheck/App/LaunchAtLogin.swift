import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled: Bool

    private static let enabledByDefaultKey = "launchAtLogin.enabledByDefault"

    static func bundled(defaults: UserDefaults = .standard) -> LaunchAtLogin? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        if !defaults.bool(forKey: enabledByDefaultKey) {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: enabledByDefaultKey)
        }
        return LaunchAtLogin()
    }

    private init() {
        isEnabled = Self.currentStatus
    }

    private static var currentStatus: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        isEnabled = Self.currentStatus
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
        refresh()
    }
}
