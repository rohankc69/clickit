import AppKit
import SwiftUI

/// Owns the Settings window directly instead of relying on SwiftUI's `Settings`
/// scene.
///
/// `NSApp.sendAction(showSettingsWindow:)` is the documented way to open that
/// scene, but in an accessory application it reports success while nothing
/// appears on screen — there is no Dock icon or menu bar to fall back on, so the
/// user is simply left with a button that seems to do nothing. Managing the
/// window here makes showing it deterministic, and means it can be raised from
/// the popover, the panel and the status-item menu alike.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var window: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        // An accessory app is not active by default, so without this the window
        // opens behind whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(environment: environment))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Clickit Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false  // reopened rather than rebuilt
        window.delegate = self
        window.center()
        return window
    }

    /// Closing Settings must not leave an accessory app active with no windows,
    /// which strands the user with no visible way back to what they were doing.
    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }
}
