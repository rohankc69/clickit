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
    @ObservationIgnored private let loginItem: LoginItemManaging

    /// Read fresh each time rather than cached: the user can grant or revoke it
    /// in System Settings while Clickit is running, and a stale answer would
    /// show the wrong state indefinitely.
    var isAccessibilityTrusted: Bool { accessibility.isTrusted }

    func requestAccessibilityAccess() {
        accessibility.requestAccess()
    }

    /// Clears the stale authorisation and immediately asks again.
    ///
    /// One action rather than two, because the reset on its own leaves the user
    /// worse off than before: no record at all, and no prompt to make a new one.
    /// Returns whether the reset worked, so the caller can fall back to sending
    /// the user to System Settings by hand.
    @discardableResult
    func repairAccessibilityAccess() -> Bool {
        guard accessibility.resetAuthorization() else { return false }
        // Clearing the record also clears the "already asked" flag, so the
        // system prompt can appear again.
        accessibility.requestAccess()
        settingsStore.settings.hasHadAccessibilityAccess = false
        return true
    }

    /// Why automatic pasting is or is not working, in the terms the user needs
    /// in order to fix it.
    enum AccessibilityStatus: Equatable {
        /// Either granted, or not needed because automatic pasting is off.
        case satisfied
        /// Wanted but never granted.
        case notGranted
        /// Granted once and no longer honoured. Practically always an update:
        /// the new bundle has a different signature, so macOS stops matching the
        /// existing grant. Re-toggling the old entry does not fix it -- it has to
        /// be removed and added again.
        case revoked
    }

    var accessibilityStatus: AccessibilityStatus {
        guard settingsStore.settings.autoPasteEnabled else { return .satisfied }
        if isAccessibilityTrusted { return .satisfied }
        return settingsStore.settings.hasHadAccessibilityAccess ? .revoked : .notGranted
    }

    /// Latches the fact that access was held, so a later loss can be recognised.
    ///
    /// Called on launch and whenever the UI is about to report on the state, as
    /// the user can change it in System Settings while Clickit is running.
    func refreshAccessibilityState() {
        guard isAccessibilityTrusted,
              !settingsStore.settings.hasHadAccessibilityAccess
        else { return }
        settingsStore.settings.hasHadAccessibilityAccess = true
    }

    // MARK: - Launch at login

    /// Whether macOS launches Clickit when the user logs in.
    ///
    /// Read live from the system, which owns this state: the user can also change
    /// it in System Settings, and Clickit should reflect that rather than a cached
    /// copy.
    var opensAtLogin: Bool { loginItem.isEnabled }

    /// Shown in Settings next to the toggle when macOS refuses the change, the
    /// same way `shortcutError` reports a shortcut that could not be claimed.
    var loginItemError: String?

    /// Turns launch at login on or off at the user's request.
    ///
    /// The system owns the actual state, so a failure leaves the toggle
    /// reflecting reality rather than a value that never took. Marking the item
    /// configured retires the first-launch default: from here on this is the
    /// user's choice.
    func setOpensAtLogin(_ enabled: Bool) {
        settingsStore.settings.hasConfiguredLoginItem = true
        do {
            try loginItem.setEnabled(enabled)
            loginItemError = nil
            ClickitLog.app.notice("Launch at login \(enabled ? "enabled" : "disabled", privacy: .public)")
        } catch {
            ClickitLog.app.error(
                "Could not \(enabled ? "enable" : "disable", privacy: .public) launch at login: \(error.localizedDescription, privacy: .public)"
            )
            loginItemError = "macOS would not change the login item. \(error.localizedDescription)"
        }
    }

    /// Applies the default — on — exactly once, on the first launch.
    ///
    /// After the latch is set it never runs again, so a user who turns it off is
    /// not fought on the next launch. A failure here is not fatal: the toggle in
    /// Settings still works, and an unsigned build macOS will not verify is the
    /// usual reason it cannot register itself.
    private func applyDefaultLoginItemIfNeeded() {
        guard !settingsStore.settings.hasConfiguredLoginItem else { return }
        settingsStore.settings.hasConfiguredLoginItem = true
        do {
            try loginItem.setEnabled(true)
            ClickitLog.app.notice("Enabled launch at login by default")
        } catch {
            ClickitLog.app.error("Could not enable launch at login by default: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Dismissed for this launch only. A permission the user has chosen to
    /// ignore should not keep interrupting them, but it also should not be
    /// silently forgotten across launches while the feature stays broken.
    var isAccessibilityNoticeDismissed = false

    var shouldShowAccessibilityNotice: Bool {
        !isAccessibilityNoticeDismissed && accessibilityStatus != .satisfied
    }

    /// One line describing the state a bug report is most likely to turn on.
    ///
    /// Logged unconditionally, including the healthy case. A message that only
    /// appears when something is wrong cannot distinguish "working" from "the
    /// check never ran", which is precisely the ambiguity that made an earlier
    /// permission fault so slow to pin down.
    func logDiagnosticState() {
        let status: String = switch accessibilityStatus {
        case .satisfied: isAccessibilityTrusted ? "granted" : "not needed"
        case .notGranted: "not granted"
        case .revoked: "no longer honoured, most likely after an update"
        }
        ClickitLog.app.notice(
            """
            State: accessibility \(status, privacy: .public); \
            automatic pasting \(self.settingsStore.settings.autoPasteEnabled ? "on" : "off", privacy: .public); \
            recording \(self.isMonitoringPaused ? "paused" : "on", privacy: .public); \
            \(self.items.count, privacy: .public) items
            """
        )
    }

    /// Everything the maintainer needs to act on a report, and nothing that
    /// could carry clipboard contents: counts and states only, never an item.
    func diagnosticSummary() -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let accessibility: String = switch accessibilityStatus {
        case .satisfied: isAccessibilityTrusted ? "granted" : "not required"
        case .notGranted: "not granted"
        case .revoked: "reset, most likely by an update"
        }

        return """
        Clickit \(version) (\(build))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)

        Accessibility: \(accessibility)
        Automatic pasting: \(settingsStore.settings.autoPasteEnabled ? "on" : "off")
        Shortcut: \(settingsStore.settings.openShortcut.displayString)\(shortcutError.map { " (failed: \($0))" } ?? "")
        Recording: \(isMonitoringPaused ? "paused" : "on")
        Poll interval: \(settingsStore.settings.pollInterval)s

        Items: \(items.count) (\(items.filter(\.isPinned).count) pinned)
        Storage: \(FileSizeFormatter.string(fromByteCount: clipboardStore.totalByteSize))
        History on disk: \(clipboardStore is SQLiteClipboardStore ? "yes" : "no, running in memory")
        Last error: \(lastErrorMessage ?? "none")
        """
    }

    /// Puts the summary on the clipboard for pasting into an issue.
    ///
    /// Deliberately routed through the monitor's ignore list, so asking for
    /// diagnostics does not itself become a history entry.
    func copyDiagnosticsToClipboard() {
        let changeCount = pasteboard.write(.text(diagnosticSummary()))
        monitor.ignoreChange(count: changeCount)
        ClickitLog.app.notice("Copied diagnostics to the clipboard")
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
        accessibility: AccessibilityAuthorizing = AccessibilityService(),
        loginItem: LoginItemManaging = LoginItemService()
    ) {
        self.settingsStore = settingsStore
        self.pasteboard = pasteboard
        self.shortcuts = shortcuts
        self.sessionReset = sessionReset
        self.accessibility = accessibility
        self.loginItem = loginItem

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
            ClickitLog.storage.notice("Opened clipboard history database with \(store.items.count, privacy: .public) items")
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
        applyDefaultLoginItemIfNeeded()
        refreshAccessibilityState()
        logDiagnosticState()
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
        // The banner already explains the permission and offers the fix, so
        // this only has to cover what happened to the item just picked.
        isAccessibilityNoticeDismissed = false
        lastErrorMessage = "Copied. Press Command-V to paste it."
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
