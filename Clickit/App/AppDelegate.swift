import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment: AppEnvironment
    private let accessibility: AccessibilityService
    private var menuBarController: MenuBarController?
    private var settingsWindow: SettingsWindowController?

    /// Built here rather than as default values on the properties themselves.
    /// Swift 6.0 crashes in SILGen lowering a stored-property initializer that
    /// calls a main-actor isolated initializer, which takes the CI toolchain
    /// down with it. Assigning inside `init` avoids that code path and is
    /// identical in behaviour.
    override init() {
        environment = AppEnvironment()
        accessibility = AccessibilityService()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces alongside `LSUIElement`: keeps the Dock icon hidden
        // even when the app is launched straight from a build directory.
        NSApp.setActivationPolicy(.accessory)

        let settingsWindow = SettingsWindowController(environment: environment)
        self.settingsWindow = settingsWindow

        let quickPaste = QuickPasteController(
            environment: environment,
            accessibility: accessibility,
            caretLocator: CaretLocator(accessibility: accessibility),
            pasteSimulator: PasteSimulator(accessibility: accessibility),
            openSettings: { settingsWindow.show() }
        )
        menuBarController = MenuBarController(
            environment: environment,
            quickPaste: quickPaste,
            settingsWindow: settingsWindow
        )
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
