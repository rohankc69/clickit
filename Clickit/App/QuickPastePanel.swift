import AppKit
import SwiftUI

/// Borderless panel shown on the active display when the global shortcut fires.
///
/// A panel rather than the menu-bar `NSPopover`, because a popover is anchored
/// to the view it was opened from and cannot be positioned arbitrarily on
/// screen. `.nonactivatingPanel` plus a `canBecomeKey` override is the standard
/// combination for a window that takes keystrokes without making its app the
/// active one.
final class QuickPastePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none

        // Follow the user across spaces and appear over full-screen apps, which
        // is where a picker is most needed and least reachable.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    /// Without this the search field never receives keystrokes.
    override var canBecomeKey: Bool { true }

    /// Staying out of the main-window chain keeps the previously frontmost app
    /// as the one auto-paste will target.
    override var canBecomeMain: Bool { false }
}

/// Owns the panel, its placement, and the focus handoff around auto-paste.
@MainActor
final class QuickPasteController {
    private let environment: AppEnvironment
    private let caretLocator: CaretLocating
    private let pasteSimulator: PasteSimulating
    private let accessibility: AccessibilityAuthorizing
    private let openSettings: () -> Void

    private var panel: QuickPastePanel?
    private var localMonitor: Any?
    private var isPastePending = false

    /// The application the user was typing in when the panel opened. Recorded
    /// because showing the panel takes focus, and auto-paste has to give it
    /// back before the keystroke will land anywhere useful.
    private var previousApplication: NSRunningApplication?

    init(
        environment: AppEnvironment,
        accessibility: AccessibilityAuthorizing,
        caretLocator: CaretLocating,
        pasteSimulator: PasteSimulating,
        openSettings: @escaping () -> Void
    ) {
        self.environment = environment
        self.accessibility = accessibility
        self.caretLocator = caretLocator
        self.pasteSimulator = pasteSimulator
        self.openSettings = openSettings
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Presentation

    func toggle() {
        isVisible ? dismiss() : present()
    }

    func present() {
        if !isVisible {
            rememberFrontmostApplication()
        }

        let panel: QuickPastePanel
        let panelSize: CGSize
        if let existing = self.panel, existing.isVisible {
            panel = existing
            panelSize = existing.frame.size
        } else {
            panelSize = QuickPasteSurfaceLayout.size(
                itemCount: environment.items.count,
                hasError: environment.lastErrorMessage != nil
            )
            panel = makePanel(size: panelSize)
            self.panel = panel
        }

        let displays = NSScreen.screens.map {
            QuickPasteDisplay(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let preferredDisplay = NSScreen.main.map {
            QuickPasteDisplay(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        panel.setFrame(
            QuickPasteLayout.frame(
                anchoredTo: caretLocator.anchor(),
                panelSize: panelSize,
                displays: displays,
                preferredDisplay: preferredDisplay
            ),
            display: false
        )
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installDismissMonitor()
    }

    func dismiss() {
        removeDismissMonitor()
        panel?.orderOut(nil)
    }

    func rememberFrontmostApplication() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            previousApplication = nil
            return
        }
        previousApplication = frontmost
    }

    private func makePanel(size: CGSize) -> QuickPastePanel {
        let panel = QuickPastePanel(
            contentRect: NSRect(origin: .zero, size: size)
        )
        let root = MenuBarPopoverView(
            environment: environment,
            onClose: { [weak self] in self?.dismiss() },
            onOpenSettings: { [weak self] in
                self?.dismiss()
                self?.openSettings()
            },
            onActivate: { [weak self] in self?.finishPaste() },
            presentation: .quickPaste,
            surfaceSize: size
        )
        // A borderless window draws nothing of its own, so the material, the
        // rounded corners and the hairline that a popover would have supplied
        // all have to be built here.
        let shape = RoundedRectangle(
            cornerRadius: ClickitDesign.surfaceCornerRadius,
            style: .continuous
        )
        let decorated = root
            .background(VisualEffectBackground())
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.separator, lineWidth: 0.5)
            }

        let hosting = NSHostingView(rootView: decorated)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        return panel
    }

    // MARK: - Dismissal

    /// Clicking outside a borderless panel does not close it automatically.
    private func installDismissMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    private func removeDismissMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    // MARK: - Auto-paste

    /// Called after an item has been written to the clipboard.
    ///
    /// Ordering matters and is the fiddly part of the whole feature: the panel
    /// has to go away, the original application has to be frontmost again, and
    /// only then can the keystroke be posted. Activation is asynchronous, so the
    /// paste is deferred rather than posted immediately.
    private func finishPaste() {
        dismiss()

        guard environment.settingsStore.settings.autoPasteEnabled else {
            return
        }
        guard accessibility.isTrusted else {
            environment.reportAutoPasteUnavailable()
            return
        }
        guard let previousApplication, previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        isPastePending = true
        guard previousApplication.activate() else {
            isPastePending = false
            environment.reportPasteTargetChanged()
            return
        }
        let target = previousApplication.bundleIdentifier ?? "unknown"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            defer { self.isPastePending = false }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == previousApplication.processIdentifier else {
                self.environment.reportPasteTargetChanged()
                return
            }
            let posted = pasteSimulator.pasteIntoFrontmostApplication()
            if !posted {
                self.environment.reportAutoPasteUnavailable()
            }
            // Logged either way. "Pasted into nothing" and "never tried" look
            // identical from the outside, and only one of them is a bug here.
            ClickitLog.shortcut.notice(
                "Auto-paste into \(target, privacy: .public): \(posted ? "posted" : "not posted", privacy: .public)"
            )
        }
    }
}
