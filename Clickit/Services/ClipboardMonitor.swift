import Foundation
import Observation

/// A pasteboard change the monitor decided is worth recording.
struct CapturedClipboardContent: Equatable {
    let payload: PasteboardPayload
    let sourceApplication: String?
    let capturedAt: Date
}

/// Watches `NSPasteboard` for changes and reports the ones worth keeping.
///
/// The monitor deliberately knows nothing about storage or SwiftUI. It reads
/// through `PasteboardServicing`, applies the "should this be captured at all"
/// rules, and hands the result to `onCapture`. Wiring lives in `AppEnvironment`.
///
/// macOS offers no change notification for the pasteboard, so polling the
/// change count is the only available mechanism. The poll itself is cheap — it
/// reads a single integer and only touches pasteboard contents when that
/// integer moved.
@MainActor
@Observable
final class ClipboardMonitor {
    private(set) var isRunning = false

    @ObservationIgnored private let pasteboard: PasteboardServicing
    @ObservationIgnored private let settingsProvider: @MainActor () -> ClickitSettings
    @ObservationIgnored private let onCapture: @MainActor (CapturedClipboardContent) -> Void
    @ObservationIgnored private let now: @Sendable () -> Date

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastChangeCount = 0
    /// Change count produced by Clickit's own write, so restoring an item does
    /// not immediately read back as a fresh copy.
    @ObservationIgnored private var suppressedChangeCount: Int?

    init(
        pasteboard: PasteboardServicing,
        settingsProvider: @escaping @MainActor () -> ClickitSettings,
        now: @escaping @Sendable () -> Date = { Date() },
        onCapture: @escaping @MainActor (CapturedClipboardContent) -> Void
    ) {
        self.pasteboard = pasteboard
        self.settingsProvider = settingsProvider
        self.now = now
        self.onCapture = onCapture
    }

    // No `deinit` cleanup: the run loop owns the timer, so tearing it down from
    // a deinit that may run off the main actor would be a data race. Callers own
    // the lifecycle and must call `stop()` — `AppEnvironment.stop()` does.

    // MARK: - Lifecycle

    /// Begins polling. The pasteboard's current state becomes the baseline and
    /// is *not* captured, so resuming after a pause does not retroactively
    /// swallow whatever was copied while monitoring was off.
    func start() {
        guard !isRunning else { return }
        lastChangeCount = pasteboard.changeCount
        isRunning = true
        scheduleTimer()
        ClickitLog.clipboard.info("Clipboard monitoring started")
    }

    func stop() {
        guard isRunning else { return }
        timer?.invalidate()
        timer = nil
        isRunning = false
        ClickitLog.clipboard.info("Clipboard monitoring stopped")
    }

    /// Re-reads the poll interval from settings.
    func restartIfRunning() {
        guard isRunning else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    private func scheduleTimer() {
        let interval = max(0.1, settingsProvider().pollInterval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        // `.common` keeps polling alive while a menu or the popover is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Called by whoever writes to the pasteboard on Clickit's behalf.
    func ignoreChange(count: Int) {
        suppressedChangeCount = count
    }

    // MARK: - Polling

    func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if suppressedChangeCount == changeCount {
            suppressedChangeCount = nil
            return
        }

        guard let snapshot = pasteboard.read() else { return }

        let settings = settingsProvider()
        if let source = snapshot.sourceApplication,
           settings.excludedBundleIdentifiers.contains(source) {
            ClickitLog.clipboard.debug("Skipped copy from excluded app \(source, privacy: .public)")
            return
        }

        onCapture(
            CapturedClipboardContent(
                payload: snapshot.payload,
                sourceApplication: snapshot.sourceApplication,
                capturedAt: now()
            )
        )
    }
}
