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
    @ObservationIgnored private let shortcuts: GlobalShortcutRegistering

    /// Surfaced in the popover rather than swallowed. Cleared on the next
    /// successful capture or when the user dismisses it.
    var lastErrorMessage: String?

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
        shortcuts: GlobalShortcutRegistering = ShortcutService()
    ) {
        self.settingsStore = settingsStore
        self.pasteboard = pasteboard
        self.shortcuts = shortcuts

        let resolvedImageStorage = imageStorage ?? Self.makeImageStorage()
        self.clipboardStore = clipboardStore ?? InMemoryClipboardStore(imageStorage: resolvedImageStorage)
        self.imageStorage = resolvedImageStorage

        self.monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            settingsProvider: { [settingsStore] in settingsStore.settings }
        ) { [weak self] captured in
            self?.handle(captured)
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
        runCleanup()
        if !settingsStore.settings.isMonitoringPaused {
            monitor.start()
        }
        registerGlobalShortcutIfAvailable()
    }

    func stop() {
        monitor.stop()
        shortcuts.unregister()
    }

    /// Global shortcuts are not implemented yet; the failure is expected and
    /// only logged so the rest of startup continues normally.
    private func registerGlobalShortcutIfAvailable() {
        guard shortcuts.isSupported else { return }
        do {
            try shortcuts.register(.default) { [weak self] in
                self?.openPopoverRequested?()
            }
        } catch {
            ClickitLog.shortcut.error("\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Set by `MenuBarController`; invoked by the global shortcut once it exists.
    @ObservationIgnored var openPopoverRequested: (@MainActor () -> Void)?

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
