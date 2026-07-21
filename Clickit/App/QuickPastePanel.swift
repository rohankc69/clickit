import AppKit
import SwiftUI

/// Borderless panel shown at the text caret when the global shortcut fires.
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

    /// The application the user was typing in when the panel opened. Recorded
    /// because showing the panel takes focus, and auto-paste has to give it
    /// back before the keystroke will land anywhere useful.
    private var previousApplication: NSRunningApplication?

    private static let panelSize = NSSize(
        width: ClickitDesign.surfaceSize.width,
        height: ClickitDesign.surfaceSize.height
    )
    /// Gap between the caret and the panel, so the panel never covers the text
    /// being edited.
    private static let caretGap: CGFloat = 8

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
        previousApplication = NSWorkspace.shared.frontmostApplication

        let panel = panel ?? makePanel()
        self.panel = panel

        panel.setFrame(frame(anchoredTo: caretLocator.anchorRect()), display: false)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installDismissMonitor()
    }

    func dismiss() {
        removeDismissMonitor()
        panel?.orderOut(nil)
    }

    private func makePanel() -> QuickPastePanel {
        let panel = QuickPastePanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize)
        )
        let root = MenuBarPopoverView(
            environment: environment,
            onClose: { [weak self] in self?.dismiss() },
            onOpenSettings: { [weak self] in
                self?.dismiss()
                self?.openSettings()
            },
            onActivate: { [weak self] in self?.finishPaste() }
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
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = hosting
        return panel
    }

    /// Places the panel just below the caret, nudged back on screen when the
    /// caret sits near an edge.
    private func frame(anchoredTo anchor: CGRect) -> NSRect {
        let size = Self.panelSize
        var origin = CGPoint(
            x: anchor.minX,
            y: anchor.minY - size.height - Self.caretGap
        )

        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        // Not enough room underneath: flip above the caret instead of clamping
        // to the bottom of the screen, which would cover what is being edited.
        if origin.y < visible.minY + 8 {
            let above = anchor.maxY + Self.caretGap
            origin.y = above + size.height > visible.maxY ? visible.minY + 8 : above
        }
        return NSRect(origin: origin, size: size)
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

        guard environment.settingsStore.settings.autoPasteEnabled else { return }
        guard accessibility.isTrusted else {
            environment.reportAutoPasteUnavailable()
            return
        }
        guard let previousApplication, previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        previousApplication.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.pasteSimulator.pasteIntoFrontmostApplication()
        }
    }
}
