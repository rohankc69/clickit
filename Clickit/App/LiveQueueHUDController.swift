import AppKit
import Observation
import SwiftUI

/// Floating surface that keeps queue controls available without taking focus
/// from the app receiving copies and queued pastes.
final class LiveQueueHUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = true
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LiveQueueHUDController {
    private let environment: AppEnvironment
    private let pasteSimulator: PasteSimulating
    private let accessibility: AccessibilityAuthorizing
    private let panel: LiveQueueHUDPanel
    private var screenObserver: NSObjectProtocol?

    init(
        environment: AppEnvironment,
        pasteSimulator: PasteSimulating,
        accessibility: AccessibilityAuthorizing
    ) {
        self.environment = environment
        self.pasteSimulator = pasteSimulator
        self.accessibility = accessibility
        panel = LiveQueueHUDPanel(contentRect: .zero)

        let root = LiveQueueHUDView(environment: environment) { [weak self] in
            self?.pasteNext()
        }
        panel.contentView = NSHostingView(rootView: root)

        updatePresentation()
        observeQueueState()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updatePresentation() }
        }
    }

    /// Copies the head of the queue, then pastes it when auto-paste is on and
    /// Accessibility is available. This is the manual fallback for a missing
    /// Input Monitoring grant.
    private func pasteNext() {
        guard environment.advancePasteQueue() != nil else { return }

        guard environment.settingsStore.settings.autoPasteEnabled else {
            // The item is on the clipboard. Pause so the user's own Command-V
            // pastes it instead of advancing to the following position.
            environment.pauseLiveQueue()
            return
        }
        guard accessibility.isTrusted else {
            environment.pauseLiveQueue()
            environment.reportAutoPasteUnavailable()
            return
        }
        // Clicking the HUD must not paste into Clickit itself.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            != Bundle.main.bundleIdentifier
        else {
            environment.pauseLiveQueue()
            return
        }

        if !pasteSimulator.pasteIntoFrontmostApplication() {
            environment.pauseLiveQueue()
            environment.reportAutoPasteUnavailable()
        }
    }

    private func observeQueueState() {
        withObservationTracking {
            _ = environment.isLiveQueueActive
            _ = environment.pasteQueue
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updatePresentation()
                self.observeQueueState()
            }
        }
    }

    private func updatePresentation() {
        let shouldShow = LiveQueueHUDLayout.shouldShow(
            isLiveQueueActive: environment.isLiveQueueActive,
            queueCount: environment.pasteQueue.count
        )
        guard shouldShow else {
            panel.orderOut(nil)
            return
        }

        // `screens.first` is the display with the macOS menu bar: the user's
        // configured main display, not whichever display currently has focus.
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        let frame = LiveQueueHUDLayout.frame(
            in: screen.visibleFrame,
            queueCount: environment.pasteQueue.count
        )
        panel.setFrame(frame, display: panel.isVisible, animate: panel.isVisible)
        panel.orderFrontRegardless()
    }
}
