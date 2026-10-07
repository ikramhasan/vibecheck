import AppKit
import CompanionCore
import SwiftUI

/// Owns the single Settings window. The app is an accessory (no Dock icon, no menu
/// bar), so the window is opened from the panel and the app is activated explicitly.
@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private let store: SessionStore
    private var window: NSWindow?

    init(settings: AppSettings, store: SessionStore) {
        self.settings = settings
        self.store = store
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, store: store))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Agent Companion Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(NSSize(width: 560, height: 560))
        window.center()
        return window
    }
}
