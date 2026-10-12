import AppKit
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdater {
    private(set) var canCheckForUpdates = false

    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private let userDriverDelegate = FrontmostUpdateWindowDelegate()
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    static func bundled() -> AppUpdater? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") == nil ? nil : AppUpdater()
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                  userDriverDelegate: userDriverDelegate)
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

private final class FrontmostUpdateWindowDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        MainActor.assumeIsolated { NSApp.activate() }
    }
}
