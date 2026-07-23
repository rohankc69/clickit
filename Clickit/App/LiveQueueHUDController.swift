import AppKit
import Observation
import SwiftUI

/// Read-only floating surface that never takes focus from the app receiving
/// copies and queued pastes.
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
        ignoresMouseEvents = true
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
    private let panel: LiveQueueHUDPanel
    private var screenObserver: NSObjectProtocol?

    init(environment: AppEnvironment) {
        self.environment = environment
        panel = LiveQueueHUDPanel(contentRect: .zero)

        let root = LiveQueueHUDView(environment: environment)
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
