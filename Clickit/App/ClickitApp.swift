import SwiftUI

/// Clickit has no main window. The only SwiftUI scene is `Settings`; the
/// clipboard UI lives in a popover owned by `MenuBarController`, which the
/// delegate creates at launch.
@main
struct ClickitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(environment: appDelegate.environment)
        }
    }
}
