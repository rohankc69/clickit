import AppKit
import Foundation
import Observation

/// Composition root and the single object the popover talks to.
///
/// Views never reach for a service directly; they call intents here. That keeps
/// persistence and pasteboard access out of SwiftUI (an explicit project rule)
/// and leaves one place to look when tracing "what happens when the user clicks
/// a row".
///
/// Not in the original folder sketch — added because wiring the monitor to the
/// store, retention and pasteboard has to live *somewhere*, and putting it in
/// `AppDelegate` would have made the graph untestable.
@MainActor
@Observable
final class AppEnvironment {
    let settingsStore: SettingsStore
    let clipboardStore: any ClipboardStoring

    @ObservationIgnored let pasteboard: PasteboardServicing
    @ObservationIgnored private let imageStorage: ImageStoring
    /// Implicitly unwrapped because the monitor's capture closure captures
    /// `self`, so it cannot be built before the other stored properties exist.
    @ObservationIgnored private(set) var monitor: ClipboardMonitor!
    @ObservationIgnored private let retention = RetentionService()
    @ObservationIgnored private let sessionReset: SessionResetService
    @ObservationIgnored private let shortcuts: GlobalShortcutRegistering
    @ObservationIgnored private let accessibility: AccessibilityAuthorizing

    /// Read fresh each time rather than cached: the user can grant or revoke it
    /// in System Settings while Clickit is running, and a stale answer would
    /// show the wrong state indefinitely.
    var isAccessibilityTrusted: Bool { accessibility.isTrusted }

    func requestAccessibilityAccess() {
        accessibility.requestAccess()
    }

    /// Surfaced in the popover rather than swallowed. Cleared on the next
    /// successful capture or when the user dismisses it.
    var lastErrorMessage: String?

    /// Incremented every time something is recorded. Observers use it purely as
    /// a signal; the value itself carries no meaning beyond "it changed".
    ///
    /// A counter rather than a callback so that any number of observers can
    /// react, and so tests can assert on it without installing a spy.
    private(set) var captureCount = 0

    var isMonitoringPaused: Bool {
        settingsStore.settings.isMonitoringPaused
    }

    var items: [ClipboardItem] {
        clipboardStore.items
    }

    init(
        settingsStore: SettingsStore = SettingsStore(),
        imageStorage: ImageStoring? = nil,
        clipboardStore: (any ClipboardStoring)? = nil,
        pasteboard: PasteboardServicing = PasteboardService(),
        shortcuts: GlobalShortcutRegistering = ShortcutService(),
        sessionReset: SessionResetService = SessionResetService(),
        accessibility: AccessibilityAuthorizing = AccessibilityService()
    ) {
        self.settingsStore = settingsStore
        self.pasteboard = pasteboard
        self.shortcuts = shortcuts
        self.sessionReset = sessionReset
        self.accessibility = accessibility

        let resolvedImageStorage = imageStorage ?? Self.makeImageStorage()
        self.imageStorage = resolvedImageStorage

        // The store is built before `self` exists, so write failures are routed
        // through a relay that is pointed at `self` once initialisation is done.
        let relay = ErrorRelay()
        self.errorRelay = relay

        if let clipboardStore {
            self.clipboardStore = clipboardStore
            self.storeStartupError = nil
        } else {
            let (store, failure) = Self.makeClipboardStore(imageStorage: resolvedImageStorage, relay: relay)
            self.clipboardStore = store
            self.storeStartupError = failure
        }

        self.monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            settingsProvider: { [settingsStore] in settingsStore.settings }
        ) { [weak self] captured in
            self?.handle(captured)
        }

        relay.handler = { [weak self] error in
            self?.lastErrorMessage = error.localizedDescription
        }
    }

    /// Forwards store write failures to `AppEnvironment` once it exists.
    private final class ErrorRelay {
        var handler: ((Error) -> Void)?
    }

    @ObservationIgnored private let errorRelay: ErrorRelay
    /// Set when the database could not be opened and history fell back to
    /// memory. Surfaced on `start()`, once the UI can show it.
    @ObservationIgnored private let storeStartupError: String?

    /// Falls back to in-memory history if the database cannot be opened, so a
    /// corrupt or unwritable file costs persistence rather than the whole app.
    private static func makeClipboardStore(
        imageStorage: ImageStoring,
        relay: ErrorRelay
    ) -> (any ClipboardStoring, String?) {
        do {
            let store = try SQLiteClipboardStore(imageStorage: imageStorage) { [weak relay] error in
                relay?.handler?(error)
            }
            ClickitLog.storage.info("Opened clipboard history database with \(store.items.count, privacy: .public) items")
            return (store, nil)
        } catch {
            ClickitLog.storage.error(
                "Could not open the history database, continuing in memory: \(error.localizedDescription, privacy: .public)"
            )
            return (
                InMemoryClipboardStore(imageStorage: imageStorage),
                "History could not be saved to disk and will be lost when Clickit quits. \(error.localizedDescription)"
            )
        }
    }

    private static func makeImageStorage() -> ImageStoring {
        do {
            return try ImageStorageService()
        } catch {
            // Application Support being unavailable is close to unrecoverable,
            // but losing image history is better than refusing to launch.
            ClickitLog.storage.error(
                "Falling back to a temporary image directory: \(error.localizedDescription, privacy: .public)"
            )
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("Clickit/Images", isDirectory: true)
            return ImageStorageService(directory: fallback)
        }
    }

    // MARK: - Lifecycle

    func start() {
        if let storeStartupError {
            lastErrorMessage = storeStartupError
        }
        // Before cleanup: a restart discards the whole unpinned working set, so
        // there is no point ageing out items that are about to be dropped.
        sessionReset.resetIfSystemRestarted(store: clipboardStore, settings: settingsStore.settings)
        runCleanup()
        if !settingsStore.settings.isMonitoringPaused {
            monitor.start()
        }
        registerGlobalShortcut()
    }

    func stop() {
        monitor.stop()
        shortcuts.unregister()
    }

    /// A shortcut already claimed by another application is a normal outcome,
    /// not a crash: it is surfaced so the user can pick a different one, and
    /// the rest of startup continues either way.
    func registerGlobalShortcut() {
        guard shortcuts.isSupported else { return }
        do {
            try shortcuts.register(settingsStore.settings.openShortcut) { [weak self] in
                self?.openPopoverRequested?()
            }
            shortcutError = nil
        } catch {
            ClickitLog.shortcut.error("\(error.localizedDescription, privacy: .public)")
            shortcutError = error.localizedDescription
        }
    }

    /// Shown in Settings next to the shortcut rather than as a popover banner,
    /// since that is where the user can act on it.
    var shortcutError: String?

    /// Applies a new binding, keeping the old one if registration fails so the
    /// user is never left with no working shortcut.
    func updateShortcut(_ configuration: KeyboardShortcutConfiguration) {
        let previous = settingsStore.settings.openShortcut
        settingsStore.settings.openShortcut = configuration
        registerGlobalShortcut()
        if shortcutError != nil {
            settingsStore.settings.openShortcut = previous
            registerGlobalShortcut()
        }
    }

    /// Set by `MenuBarController`; invoked when the global shortcut fires.
    @ObservationIgnored var openPopoverRequested: (@MainActor () -> Void)?

    /// The item is on the clipboard but Clickit could not paste it, because
    /// Accessibility access has not been granted. Saying so beats appearing to
    /// do nothing.
    func reportAutoPasteUnavailable() {
        lastErrorMessage = "Copied. Press Command-V to paste — Clickit needs Accessibility access to paste for you."
    }

    // MARK: - Capture

    private func handle(_ captured: CapturedClipboardContent) {
        do {
            let item = try makeItem(from: captured)
            let isDuplicate = clipboardStore.promoteDuplicate(
                contentHash: item.contentHash,
                at: captured.capturedAt
            )
            if isDuplicate {
                // Same content already recorded — the existing row moved to the
                // top, and any freshly written image file is now redundant.
                discardUnusedImage(for: item)
            } else {
                clipboardStore.insert(item)
            }
            // Metadata only — never the clipboard contents themselves.
            ClickitLog.clipboard.info(
                """
                \(isDuplicate ? "Promoted duplicate" : "Captured new", privacy: .public) \
                \(item.type.rawValue, privacy: .public) item, \
                \(item.byteSize, privacy: .public) bytes
                """
            )
            lastErrorMessage = nil
            captureCount += 1
            runCleanup(now: captured.capturedAt)
        } catch {
            ClickitLog.clipboard.error("Failed to capture clipboard content: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
        }
    }

    private func makeItem(from captured: CapturedClipboardContent) throws -> ClipboardItem {
        switch captured.payload {
        case .text(let string):
            return ClipboardItem(
                type: .text,
                textContent: string,
                contentHash: ContentHasher.hash(text: string, type: .text),
                createdAt: captured.capturedAt,
                sourceApplication: captured.sourceApplication,
                byteSize: string.utf8.count
            )

        case .url(let url):
            let absolute = url.absoluteString
            return ClipboardItem(
                type: .url,
                textContent: absolute,
                contentHash: ContentHasher.hash(text: absolute, type: .url),
                createdAt: captured.capturedAt,
                sourceApplication: captured.sourceApplication,
                byteSize: absolute.utf8.count
            )

        case .image(let data):
            let relativePath = try imageStorage.store(data: data)
            return ClipboardItem(
                type: .image,
                imagePath: relativePath,
                contentHash: ContentHasher.hash(data: data, type: .image),
                createdAt: captured.capturedAt,
                sourceApplication: captured.sourceApplication,
                byteSize: data.count
            )
        }
    }

    private func discardUnusedImage(for item: ClipboardItem) {
        guard let imagePath = item.imagePath else { return }
        do {
            try imageStorage.delete(relativePath: imagePath)
        } catch {
            ClickitLog.storage.error("Failed to discard duplicate image: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Intents

    /// Puts the item back on the system pasteboard. Clickit never simulates a
    /// paste keystroke — the user presses Command-V themselves, which is why
    /// the app needs no Accessibility permission.
    func restore(_ item: ClipboardItem) {
        do {
            let payload = try payload(for: item)
            let changeCount = pasteboard.write(payload)
            monitor.ignoreChange(count: changeCount)
            clipboardStore.markUsed(id: item.id, at: Date())
            lastErrorMessage = nil
        } catch {
            ClickitLog.clipboard.error("Failed to restore item: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
        }
    }

    private func payload(for item: ClipboardItem) throws -> PasteboardPayload {
        switch item.type {
        case .text:
            .text(item.textContent ?? "")
        case .url:
            if let text = item.textContent, let url = URL(string: text) { .url(url) }
            else { .text(item.textContent ?? "") }
        case .image:
            .image(data: try clipboardStore.loadImageData(for: item))
        }
    }

    func imageData(for item: ClipboardItem) -> Data? {
        guard item.type == .image else { return nil }
        return try? clipboardStore.loadImageData(for: item)
    }

    func delete(_ item: ClipboardItem) {
        clipboardStore.delete(id: item.id)
    }

    func togglePin(_ item: ClipboardItem) {
        clipboardStore.setPinned(!item.isPinned, id: item.id)
    }

    /// Pinned items are kept: a user who pinned something asked for it to stay.
    func clearHistory(includingPinned: Bool = false) {
        clipboardStore.deleteAll(includingPinned: includingPinned)
    }

    func toggleMonitoring() {
        settingsStore.settings.isMonitoringPaused.toggle()
        if settingsStore.settings.isMonitoringPaused {
            monitor.stop()
        } else {
            monitor.start()
        }
    }

    func settingsChanged() {
        monitor.restartIfRunning()
        runCleanup()
    }

    func runCleanup(now: Date = Date()) {
        retention.runCleanup(store: clipboardStore, settings: settingsStore.settings, now: now)
    }
}
