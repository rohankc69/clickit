import AppKit
import SwiftUI

/// Owns the Settings window directly instead of relying on SwiftUI's `Settings`
/// scene.
///
/// `NSApp.sendAction(showSettingsWindow:)` is the documented way to open that
/// scene, but in an accessory application it reports success while nothing
/// appears on screen — there is no Dock icon or menu bar to fall back on, so the
/// user is simply left with a button that seems to do nothing.
///
/// Owning the window also buys the real preference toolbar. SwiftUI's `TabView`
/// only takes on the System Settings appearance inside a `Settings` scene;
/// anywhere else it draws an ordinary tab strip, which is the wrong control for
/// a settings window on macOS.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private let environment: AppEnvironment
    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var pane: SettingsPane = .general

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        // An accessory application is not active by default, so without this the
        // window opens behind whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: AnyView(pane.view(environment: environment)))
        hostingController = hosting

        let window = NSWindow(contentViewController: hosting)
        window.title = "Clickit Settings"
        // No minimise or resize: a settings window is sized by its content, and
        // every Apple settings window behaves this way.
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false  // reopened rather than rebuilt
        window.delegate = self

        let toolbar = NSToolbar(identifier: "ClickitSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(pane.id)
        window.toolbar = toolbar
        // The style that produces the System Settings look rather than a
        // document window's toolbar.
        window.toolbarStyle = .preference

        window.setContentSize(pane.contentSize)
        window.center()
        return window
    }

    /// Closing Settings must not leave an accessory application active with no
    /// windows, which strands the user with no visible way back to their work.
    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }

    // MARK: - Panes

    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let selected = SettingsPane(rawValue: sender.itemIdentifier.rawValue) else { return }
        pane = selected
        hostingController?.rootView = AnyView(selected.view(environment: environment))
        resize(to: selected.contentSize)
    }

    /// Panes differ in height, so the window grows and shrinks to fit rather
    /// than every pane being padded out to the tallest.
    private func resize(to contentSize: CGSize) {
        guard let window else { return }
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        var target = window.frame
        // Anchor the title bar, so the window grows downwards instead of
        // appearing to jump up the screen.
        target.origin.y += target.height - frame.height
        target.size = frame.size
        window.setFrame(target, display: true, animate: true)
    }

    // MARK: - NSToolbarDelegate

    private var paneIdentifiers: [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map { NSToolbarItem.Identifier($0.id) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneIdentifiers
    }

    /// Without this the items are buttons rather than a selection, and the
    /// current pane is never highlighted.
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneIdentifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = SettingsPane(rawValue: itemIdentifier.rawValue) else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.title
        item.paletteLabel = pane.title
        item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(selectPane(_:))
        item.isNavigational = false
        return item
    }
}
