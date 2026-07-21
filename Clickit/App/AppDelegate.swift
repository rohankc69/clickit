import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces alongside `LSUIElement`: keeps the Dock icon hidden
        // even when the app is launched straight from a build directory.
        NSApp.setActivationPolicy(.accessory)

        menuBarController = MenuBarController(environment: environment)
        environment.start()
        ClickitLog.app.info("Clickit launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.stop()
    }

    /// No windows to restore — the popover is the app.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        false
    }
}
