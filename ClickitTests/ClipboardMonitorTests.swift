import XCTest
@testable import Clickit

/// The monitor is driven by calling `poll()` directly rather than by waiting on
/// its timer, so these tests are deterministic and fast. Timer scheduling itself
/// is covered by `start()`/`stop()` state assertions only.
@MainActor
final class ClipboardMonitorTests: ClickitTestCase {
    private var pasteboard: MockPasteboardService!
    private var captured: [CapturedClipboardContent] = []
    private var monitors: [ClipboardMonitor] = []

    override func setUp() async throws {
        try await super.setUp()
        pasteboard = MockPasteboardService()
        captured = []
    }

    override func tearDown() async throws {
        // The monitor owns a run-loop timer and has no deinit cleanup by design.
        monitors.forEach { $0.stop() }
        monitors = []
        try await super.tearDown()
    }

    private func makeMonitor(settings: ClickitSettings = .default) -> ClipboardMonitor {
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            settingsProvider: { settings }
        ) { [weak self] content in
            self?.captured.append(content)
        }
        monitors.append(monitor)
        return monitor
    }

    func testCapturesNewText() {
        let monitor = makeMonitor()
        pasteboard.stage(.text("hello"))

        monitor.poll()

        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured.first?.payload, .text("hello"))
        XCTAssertEqual(captured.first?.sourceApplication, "com.example.Editor")
    }

    func testUnchangedPasteboardIsNotCapturedTwice() {
        let monitor = makeMonitor()
        pasteboard.stage(.text("hello"))

        monitor.poll()
        monitor.poll()
        monitor.poll()

        XCTAssertEqual(captured.count, 1)
    }

    func testEachDistinctChangeIsCaptured() {
        let monitor = makeMonitor()

        pasteboard.stage(.text("one"))
        monitor.poll()
        pasteboard.stage(.text("two"))
        monitor.poll()

        XCTAssertEqual(captured.map(\.payload), [.text("one"), .text("two")])
    }

    /// Restoring an item writes to the pasteboard; that write must not come
    /// back around as a fresh copy.
    func testClickitsOwnWriteIsIgnored() {
        let monitor = makeMonitor()
        let changeCount = pasteboard.write(.text("restored"))
        monitor.ignoreChange(count: changeCount)

        monitor.poll()

        XCTAssertTrue(captured.isEmpty)
    }

    func testSuppressionOnlyAppliesToTheOneWrite() {
        let monitor = makeMonitor()
        monitor.ignoreChange(count: pasteboard.write(.text("restored")))
        monitor.poll()

        pasteboard.stage(.text("typed by the user"))
        monitor.poll()

        XCTAssertEqual(captured.map(\.payload), [.text("typed by the user")])
    }

    func testUnsupportedContentIsIgnored() {
        let monitor = makeMonitor()
        pasteboard.stageUnsupportedContent()

        monitor.poll()

        XCTAssertTrue(captured.isEmpty)
    }

    func testCopiesFromExcludedApplicationsAreDropped() {
        var settings = ClickitSettings.default
        settings.excludedBundleIdentifiers = ["com.example.PasswordManager"]
        let monitor = makeMonitor(settings: settings)

        pasteboard.stage(.text("hunter2"), source: "com.example.PasswordManager")
        monitor.poll()
        XCTAssertTrue(captured.isEmpty)

        pasteboard.stage(.text("ordinary"), source: "com.example.Editor")
        monitor.poll()
        XCTAssertEqual(captured.count, 1)
    }

    func testStartStopTracksRunningState() {
        let monitor = makeMonitor()
        XCTAssertFalse(monitor.isRunning)

        monitor.start()
        XCTAssertTrue(monitor.isRunning)

        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }

    /// Resuming after a pause must not retroactively pick up whatever was
    /// copied while monitoring was off.
    func testStartingTakesTheCurrentPasteboardAsBaseline() {
        let monitor = makeMonitor()
        pasteboard.stage(.text("copied while paused"))

        monitor.start()
        monitor.poll()

        XCTAssertTrue(captured.isEmpty)
    }
}
