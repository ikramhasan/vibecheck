import AppKit

// Entry point: a menu-bar-less accessory app (no Dock icon) that owns one edge panel.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
