import SwiftUI

/// Clickit has no main window. Everything the user sees is owned by
/// `AppDelegate`: the status item, the popover, the caret panel and the Settings
/// window.
///
/// `App` requires at least one scene, so an empty `Settings` scene stands in.
/// The real Settings window is managed by `SettingsWindowController`, because
/// SwiftUI's scene cannot be shown reliably from an accessory application —
/// see that type for the detail.
@main
struct ClickitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
