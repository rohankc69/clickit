import AppKit
import Observation
import SwiftUI

/// Owns the status-bar item and the popover that hangs off it.
///
/// This is the one place Clickit reaches for AppKit rather than SwiftUI.
/// `MenuBarExtra` would cover the click-to-open case, but on macOS 14 it cannot
/// be opened programmatically, and the roadmap requires a global shortcut that
/// shows the *same* popover. `NSStatusItem` + `NSPopover` keeps that door open
/// and gives direct control over keyboard focus.
@MainActor
final class MenuBarController: NSObject {
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    /// Pending restore of the normal icon after a capture flash. Held so a
    /// rapid burst of copies does not leave the confirmation stuck on screen.
    private var flashReset: DispatchWorkItem?
    private static let flashDuration: TimeInterval = 0.45

    /// Shown at the text caret when the global shortcut fires, as opposed to the
    /// popover, which is anchored to the menu-bar icon.
    private let quickPaste: QuickPasteController
    private let settingsWindow: SettingsWindowController

    init(
        environment: AppEnvironment,
        quickPaste: QuickPasteController,
        settingsWindow: SettingsWindowController
    ) {
        self.environment = environment
        self.quickPaste = quickPaste
        self.settingsWindow = settingsWindow
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configurePopover()
        configureStatusItem()
        observeMonitoringState()
        observeCaptures()

        // Command-Shift-V opens the panel at the caret; clicking the menu-bar
        // icon still opens the popover anchored to the icon.
        environment.openPopoverRequested = { [weak self] in
            self?.closePopover()
            self?.quickPaste.present()
        }
    }

    private func configurePopover() {
        popover.behavior = .transient  // dismisses on any click outside
        popover.animates = false       // a utility popover should feel instant
        popover.contentSize = NSSize(
            width: ClickitDesign.surfaceSize.width,
            height: ClickitDesign.surfaceSize.height
        )
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                environment: environment,
                onClose: { [weak self] in self?.closePopover() },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            ClickitLog.app.error("Status item has no button; the menu bar icon will be missing")
            return
        }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let paused = environment.isMonitoringPaused
        let symbolName = paused ? "pause.circle" : "list.clipboard"
        let description = paused ? "Clickit — monitoring paused" : "Clickit — monitoring clipboard"

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        button.image?.isTemplate = true
        button.toolTip = description
    }

    /// Re-arms after every change: `withObservationTracking` fires once.
    private func observeMonitoringState() {
        withObservationTracking {
            _ = environment.isMonitoringPaused
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateStatusIcon()
                self.observeMonitoringState()
            }
        }
    }

    private func observeCaptures() {
        withObservationTracking {
            _ = environment.captureCount
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.flashCapture()
                self.observeCaptures()
            }
        }
    }

    /// Briefly swaps the icon for a confirmation mark.
    ///
    /// macOS gives no feedback when something reaches the clipboard, least of
    /// all a screenshot, so this is the only signal that Clickit recorded it.
    /// The icon is swapped rather than animated: menu-bar items sit next to
    /// system indicators, and movement there reads as something being wrong.
    private func flashCapture() {
        guard environment.settingsStore.settings.flashOnCapture,
              let button = statusItem.button
        else { return }

        // Showing a confirmation over a paused icon would contradict itself.
        guard !environment.isMonitoringPaused else { return }

        flashReset?.cancel()
        button.image = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "Clickit captured an item"
        )
        button.image?.isTemplate = true

        let reset = DispatchWorkItem { [weak self] in
            self?.updateStatusIcon()
        }
        flashReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashDuration, execute: reset)
    }

    // MARK: - Interaction

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        quickPaste.rememberFrontmostApplication()
        // An accessory app is not active by default; without this the popover
        // opens but the search field never receives keystrokes.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let pauseTitle = environment.isMonitoringPaused ? "Resume Monitoring" : "Pause Monitoring"
        menu.addItem(withTitle: pauseTitle, action: #selector(toggleMonitoring), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsMenuItem), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Clickit", action: #selector(quit), keyEquivalent: "q")
            .target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach immediately so the next left click opens the popover instead
        // of re-opening this menu.
        statusItem.menu = nil
    }

    @objc private func toggleMonitoring() {
        environment.toggleMonitoring()
    }

    @objc private func openSettingsMenuItem() {
        openSettings()
    }

    func openSettings() {
        closePopover()
        settingsWindow.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
