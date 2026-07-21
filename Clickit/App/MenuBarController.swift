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

    init(environment: AppEnvironment) {
        self.environment = environment
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configurePopover()
        configureStatusItem()
        observeMonitoringState()

        environment.openPopoverRequested = { [weak self] in
            self?.showPopover()
        }
    }

    private func configurePopover() {
        popover.behavior = .transient  // dismisses on any click outside
        popover.animates = false       // a utility popover should feel instant
        popover.contentSize = NSSize(width: 360, height: 420)
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
        NSApp.activate(ignoringOtherApps: true)
        // The selector behind the standard Settings scene. It was renamed in
        // macOS 13, so both spellings are attempted before giving up.
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil),
           !NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) {
            ClickitLog.app.error("Could not open the Settings window")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
