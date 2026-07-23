import XCTest
@testable import Clickit

/// End-to-end coverage of the milestone flow: a copy is observed, recorded, and
/// can be put back on the pasteboard.
@MainActor
final class AppEnvironmentTests: ClickitTestCase {
    private var pasteboard: MockPasteboardService!
    private var environment: AppEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        pasteboard = MockPasteboardService()
        environment = makeEnvironment(pasteboard: pasteboard)
    }

    override func tearDown() async throws {
        environment.stop()
        environment = nil
        try await super.tearDown()
    }

    // MARK: - Capture

    func testCopiedTextBecomesAHistoryItem() {
        pasteboard.stage(.text("first copy"))
        environment.monitor.poll()

        XCTAssertEqual(environment.items.count, 1)
        let item = environment.items.first
        XCTAssertEqual(item?.type, .text)
        XCTAssertEqual(item?.textContent, "first copy")
        XCTAssertEqual(item?.byteSize, 10)
    }

    func testCopiedURLIsClassifiedAsALink() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/page"))
        pasteboard.stage(.url(url))
        environment.monitor.poll()

        XCTAssertEqual(environment.items.first?.type, .url)
        XCTAssertEqual(environment.items.first?.textContent, "https://example.com/page")
    }

    func testCopiedImageIsWrittenToDiskAndReferencedByPath() throws {
        let data = Data(repeating: 0xAB, count: 512)
        pasteboard.stage(.image(data: data))
        environment.monitor.poll()

        let item = try XCTUnwrap(environment.items.first)
        XCTAssertEqual(item.type, .image)
        XCTAssertNil(item.textContent)
        XCTAssertEqual(item.byteSize, 512)
        XCTAssertTrue(try imageFileExists(item))
        XCTAssertEqual(try store.loadImageData(for: item), data)
    }

    func testCopyingTheSameTextTwiceKeepsOneEntryAndMovesItToTheTop() {
        pasteboard.stage(.text("repeated"))
        environment.monitor.poll()
        pasteboard.stage(.text("something else"))
        environment.monitor.poll()
        pasteboard.stage(.text("repeated"))
        environment.monitor.poll()

        XCTAssertEqual(environment.items.count, 2)
        XCTAssertEqual(environment.items.first?.textContent, "repeated")
    }

    /// A duplicate image must not leave its freshly written file behind.
    func testDuplicateImageDoesNotLeakAFile() throws {
        let data = Data(repeating: 0x11, count: 256)
        pasteboard.stage(.image(data: data))
        environment.monitor.poll()
        pasteboard.stage(.text("in between"))
        environment.monitor.poll()
        pasteboard.stage(.image(data: data))
        environment.monitor.poll()

        XCTAssertEqual(environment.items.count, 2)
        let filesOnDisk = try FileManager.default.contentsOfDirectory(atPath: imageDirectory.path)
        XCTAssertEqual(filesOnDisk.count, 1)
    }

    // MARK: - Restore

    func testRestoringPutsTextBackOnThePasteboard() throws {
        pasteboard.stage(.text("older"))
        environment.monitor.poll()
        pasteboard.stage(.text("newer"))
        environment.monitor.poll()

        let older = try XCTUnwrap(environment.items.last)
        environment.restore(older)

        XCTAssertEqual(pasteboard.writtenPayloads, [.text("older")])
        // Restoring counts as use, so it becomes the most recent entry.
        XCTAssertEqual(environment.items.first?.id, older.id)
    }

    func testRestoringDoesNotRecordAnewCopy() {
        pasteboard.stage(.text("only entry"))
        environment.monitor.poll()

        environment.restore(environment.items[0])
        environment.monitor.poll()

        XCTAssertEqual(environment.items.count, 1)
    }

    func testRestoringAnImageWritesItsBytes() throws {
        let data = Data(repeating: 0x7F, count: 128)
        pasteboard.stage(.image(data: data))
        environment.monitor.poll()

        environment.restore(try XCTUnwrap(environment.items.first))

        XCTAssertEqual(pasteboard.writtenPayloads, [.image(data: data)])
    }

    func testRestoringAnImageWhoseFileVanishedSurfacesAnError() throws {
        let data = Data(repeating: 0x22, count: 64)
        pasteboard.stage(.image(data: data))
        environment.monitor.poll()
        let item = try XCTUnwrap(environment.items.first)
        try FileManager.default.removeItem(at: imageStorage.url(forRelativePath: try XCTUnwrap(item.imagePath)))

        environment.restore(item)

        XCTAssertTrue(pasteboard.writtenPayloads.isEmpty)
        XCTAssertNotNil(environment.lastErrorMessage)
    }

    // MARK: - Global shortcuts

    func testStartRegistersAllGlobalShortcuts() {
        let shortcuts = StubShortcutService()
        environment = makeEnvironment(pasteboard: pasteboard, shortcuts: shortcuts)

        environment.start()

        XCTAssertEqual(shortcuts.configurations[.openClickit], .default)
        XCTAssertEqual(shortcuts.configurations[.captureSelection], .captureSelection)
        XCTAssertEqual(shortcuts.configurations[.toggleLiveQueue], .toggleLiveQueue)
    }

    func testLiveQueueShortcutTogglesWithoutOpeningPicker() {
        let shortcuts = StubShortcutService()
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            liveQueuePasteInterceptor: interceptor
        )
        var openCount = 0
        environment.openPopoverRequested = { openCount += 1 }
        environment.start()

        shortcuts.trigger(.toggleLiveQueue)

        XCTAssertTrue(environment.isLiveQueueActive)
        XCTAssertTrue(interceptor.isActive)
        XCTAssertEqual(openCount, 0)

        shortcuts.trigger(.toggleLiveQueue)

        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
        XCTAssertEqual(openCount, 0)
    }

    func testLiveQueueShortcutUsesOptionShiftV() {
        let shortcut = KeyboardShortcutConfiguration.toggleLiveQueue

        XCTAssertEqual(shortcut.keyCode, 0x09)
        XCTAssertTrue(shortcut.modifierFlags.contains(.option))
        XCTAssertTrue(shortcut.modifierFlags.contains(.shift))
        XCTAssertFalse(shortcut.modifierFlags.contains(.command))
        XCTAssertFalse(shortcut.modifierFlags.contains(.control))
    }

    func testScreenshotShortcutStartsInteractiveClipboardCapture() {
        let shortcuts = StubShortcutService()
        let screenshots = StubScreenshotService()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            screenshots: screenshots
        )
        environment.start()

        shortcuts.trigger(.captureSelection)

        XCTAssertEqual(screenshots.captureCount, 1)
    }

    func testOpenShortcutStillWorksAfterScreenshotRegistration() {
        let shortcuts = StubShortcutService()
        environment = makeEnvironment(pasteboard: pasteboard, shortcuts: shortcuts)
        var openCount = 0
        environment.openPopoverRequested = { openCount += 1 }
        environment.start()

        shortcuts.trigger(.captureSelection)
        shortcuts.trigger(.openClickit)

        XCTAssertEqual(openCount, 1)
    }

    func testOpenShortcutOnlyOpensPicker() {
        let shortcuts = StubShortcutService()
        environment = makeEnvironment(pasteboard: pasteboard, shortcuts: shortcuts)
        var openCount = 0
        environment.openPopoverRequested = { openCount += 1 }
        environment.start()

        shortcuts.trigger(.openClickit)

        XCTAssertEqual(openCount, 1)
        XCTAssertFalse(environment.isLiveQueueActive)
    }

    func testLiveQueueActivationFailureLeavesCommandVUntouched() {
        struct Denied: LocalizedError {
            var errorDescription: String? { "permission denied" }
        }
        let shortcuts = StubShortcutService()
        let interceptor = StubLiveQueuePasteInterceptor()
        interceptor.activationError = Denied()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            liveQueuePasteInterceptor: interceptor
        )
        environment.start()

        shortcuts.trigger(.toggleLiveQueue)

        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
        XCTAssertEqual(environment.lastErrorMessage, "permission denied")
    }

    func testScreenshotRegistrationFailureDoesNotDisableOpenShortcut() {
        struct Conflict: LocalizedError {
            var errorDescription: String? { "shortcut conflict" }
        }
        let shortcuts = StubShortcutService()
        shortcuts.registrationFailures[.captureSelection] = Conflict()
        environment = makeEnvironment(pasteboard: pasteboard, shortcuts: shortcuts)
        var openCount = 0
        environment.openPopoverRequested = { openCount += 1 }

        environment.start()
        shortcuts.trigger(.openClickit)

        XCTAssertEqual(openCount, 1)
        XCTAssertNil(environment.shortcutError)
        XCTAssertEqual(environment.screenshotShortcutError, "shortcut conflict")
    }

    func testPasteQueueRegistrationFailureDoesNotDisableOtherShortcuts() {
        struct Conflict: LocalizedError {
            var errorDescription: String? { "queue shortcut conflict" }
        }
        let shortcuts = StubShortcutService()
        shortcuts.registrationFailures[.toggleLiveQueue] = Conflict()
        environment = makeEnvironment(pasteboard: pasteboard, shortcuts: shortcuts)
        var openCount = 0
        environment.openPopoverRequested = { openCount += 1 }

        environment.start()
        shortcuts.trigger(.openClickit)
        shortcuts.trigger(.captureSelection)

        XCTAssertEqual(openCount, 1)
        XCTAssertNil(environment.shortcutError)
        XCTAssertNil(environment.screenshotShortcutError)
        XCTAssertEqual(environment.liveQueueShortcutError, "queue shortcut conflict")
    }

    func testScreenshotLaunchFailureIsSurfaced() {
        struct LaunchFailure: LocalizedError {
            var errorDescription: String? { "launch refused" }
        }
        let shortcuts = StubShortcutService()
        let screenshots = StubScreenshotService()
        screenshots.failure = LaunchFailure()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            screenshots: screenshots
        )
        environment.start()

        shortcuts.trigger(.captureSelection)

        XCTAssertEqual(environment.lastErrorMessage, "Could not start screenshot selection. launch refused")
    }

    func testScreenshotProcessFailureIsSurfaced() {
        let shortcuts = StubShortcutService()
        let screenshots = StubScreenshotService()
        screenshots.completionFailure = "Screenshot capture failed. permission denied"
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            screenshots: screenshots
        )
        environment.start()

        shortcuts.trigger(.captureSelection)

        XCTAssertEqual(environment.lastErrorMessage, "Screenshot capture failed. permission denied")
    }

    func testStopCancelsAnActiveScreenshotSelection() {
        let screenshots = StubScreenshotService()
        environment = makeEnvironment(pasteboard: pasteboard, screenshots: screenshots)

        environment.stop()

        XCTAssertEqual(screenshots.cancelCount, 1)
    }

    func testStopDeactivatesLiveQueueCommandVMonitoring() {
        let shortcuts = StubShortcutService()
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            liveQueuePasteInterceptor: interceptor
        )
        environment.start()
        shortcuts.trigger(.toggleLiveQueue)

        environment.stop()

        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
        XCTAssertEqual(interceptor.deactivationCount, 1)
    }

    // MARK: - Paste queue

    func testManuallyQueuedItemsActivateAndPasteInInsertionOrder() throws {
        let shortcuts = StubShortcutService()
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            liveQueuePasteInterceptor: interceptor
        )
        environment.start()
        pasteboard.stage(.text("first"))
        environment.monitor.poll()
        let first = try XCTUnwrap(environment.items.first)
        pasteboard.stage(.text("second"))
        environment.monitor.poll()
        let second = try XCTUnwrap(environment.items.first)

        environment.togglePasteQueue(first)
        environment.togglePasteQueue(second)

        XCTAssertEqual(environment.queuedItems.map(\.id), [first.id, second.id])
        XCTAssertEqual(environment.pasteQueuePosition(for: first), 1)
        XCTAssertEqual(environment.pasteQueuePosition(for: second), 2)
        XCTAssertTrue(environment.isLiveQueueActive)
        XCTAssertTrue(interceptor.isActive)
        XCTAssertEqual(interceptor.activationCount, 1)

        XCTAssertEqual(interceptor.triggerCommandV(), true)
        XCTAssertEqual(environment.pasteQueue, [second.id])
        XCTAssertTrue(environment.isLiveQueueActive)

        XCTAssertEqual(interceptor.triggerCommandV(), false)

        XCTAssertEqual(pasteboard.writtenPayloads, [.text("first"), .text("second")])
        XCTAssertTrue(environment.pasteQueue.isEmpty)
        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
    }

    func testOptionShiftVKillsAManuallyCreatedQueue() throws {
        let shortcuts = StubShortcutService()
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            liveQueuePasteInterceptor: interceptor
        )
        environment.start()
        pasteboard.stage(.text("discard me"))
        environment.monitor.poll()
        let item = try XCTUnwrap(environment.items.first)

        environment.togglePasteQueue(item)
        shortcuts.trigger(.toggleLiveQueue)

        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
        XCTAssertTrue(environment.pasteQueue.isEmpty)
    }

    func testManualQueueActivationFailureKeepsTheItemQueued() throws {
        struct Denied: LocalizedError {
            var errorDescription: String? { "permission denied" }
        }
        let interceptor = StubLiveQueuePasteInterceptor()
        interceptor.activationError = Denied()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            liveQueuePasteInterceptor: interceptor
        )
        pasteboard.stage(.text("keep me"))
        environment.monitor.poll()
        let item = try XCTUnwrap(environment.items.first)

        environment.togglePasteQueue(item)

        XCTAssertEqual(environment.pasteQueue, [item.id])
        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
        XCTAssertEqual(environment.lastErrorMessage, "permission denied")
    }

    func testLiveQueueAppendsEveryCaptureIncludingDuplicates() throws {
        let shortcuts = StubShortcutService()
        environment = makeEnvironment(pasteboard: pasteboard, shortcuts: shortcuts)
        environment.start()
        shortcuts.trigger(.toggleLiveQueue)

        pasteboard.stage(.text("repeated"))
        environment.monitor.poll()
        pasteboard.stage(.text("repeated"))
        environment.monitor.poll()

        let item = try XCTUnwrap(environment.items.first)
        XCTAssertEqual(environment.items.count, 1)
        XCTAssertEqual(environment.pasteQueue, [item.id, item.id])
    }

    func testOptionShiftVKillsLiveQueueAndClearsCapturedItems() throws {
        let shortcuts = StubShortcutService()
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            liveQueuePasteInterceptor: interceptor
        )
        environment.start()
        shortcuts.trigger(.toggleLiveQueue)
        pasteboard.stage(.text("keep queued"))
        environment.monitor.poll()
        let queuedID = try XCTUnwrap(environment.items.first?.id)
        XCTAssertEqual(environment.pasteQueue, [queuedID])

        shortcuts.trigger(.toggleLiveQueue)

        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
        XCTAssertTrue(environment.pasteQueue.isEmpty)
    }

    func testCommandVWithAnEmptyQueueAutomaticallyStopsLiveQueue() {
        let shortcuts = StubShortcutService()
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            liveQueuePasteInterceptor: interceptor
        )
        environment.start()
        shortcuts.trigger(.toggleLiveQueue)

        XCTAssertEqual(interceptor.triggerCommandV(), false)

        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
        XCTAssertTrue(pasteboard.writtenPayloads.isEmpty)
    }

    func testInterceptorFailureStopsLiveQueueAndKeepsRemainingItems() throws {
        let shortcuts = StubShortcutService()
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            liveQueuePasteInterceptor: interceptor
        )
        environment.start()
        pasteboard.stage(.text("queued"))
        environment.monitor.poll()
        let item = try XCTUnwrap(environment.items.first)
        environment.togglePasteQueue(item)

        interceptor.triggerFailure()

        XCTAssertEqual(environment.pasteQueue, [item.id])
        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertNotNil(environment.lastErrorMessage)
    }

    func testRemovingTheFinalQueuedItemStopsLiveQueue() throws {
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            liveQueuePasteInterceptor: interceptor
        )
        pasteboard.stage(.text("only item"))
        environment.monitor.poll()
        let item = try XCTUnwrap(environment.items.first)

        environment.togglePasteQueue(item)
        environment.togglePasteQueue(item)

        XCTAssertTrue(environment.pasteQueue.isEmpty)
        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
    }

    func testClearingPasteQueueStopsLiveQueue() throws {
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            liveQueuePasteInterceptor: interceptor
        )
        pasteboard.stage(.text("discard me"))
        environment.monitor.poll()
        environment.togglePasteQueue(try XCTUnwrap(environment.items.first))

        environment.clearPasteQueue()

        XCTAssertTrue(environment.pasteQueue.isEmpty)
        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
    }

    func testFailedQueuedImageRestoreKeepsItQueued() throws {
        let shortcuts = StubShortcutService()
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            liveQueuePasteInterceptor: interceptor
        )
        environment.start()
        pasteboard.stage(.image(data: Data(repeating: 0x44, count: 64)))
        environment.monitor.poll()
        let item = try XCTUnwrap(environment.items.first)
        environment.togglePasteQueue(item)
        try FileManager.default.removeItem(
            at: imageStorage.url(forRelativePath: try XCTUnwrap(item.imagePath))
        )

        XCTAssertEqual(interceptor.triggerCommandV(), false)

        XCTAssertEqual(environment.pasteQueue, [item.id])
        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertTrue(pasteboard.writtenPayloads.isEmpty)
        XCTAssertNotNil(environment.lastErrorMessage)
    }

    func testDeletingTheFinalQueuedItemStopsLiveQueue() throws {
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            liveQueuePasteInterceptor: interceptor
        )
        pasteboard.stage(.text("delete me"))
        environment.monitor.poll()
        let item = try XCTUnwrap(environment.items.first)
        environment.togglePasteQueue(item)

        environment.delete(item)

        XCTAssertTrue(environment.pasteQueue.isEmpty)
        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
    }

    func testClearingHistoryKeepsOnlyQueuedPinnedItems() throws {
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            liveQueuePasteInterceptor: interceptor
        )
        let pinned = makeTextItem("pinned", pinned: true)
        let recent = makeTextItem("recent")
        store.insert(pinned)
        store.insert(recent)
        environment.togglePasteQueue(pinned)
        environment.togglePasteQueue(recent)

        environment.clearHistory()

        XCTAssertEqual(environment.pasteQueue, [pinned.id])
        XCTAssertTrue(environment.isLiveQueueActive)
        XCTAssertTrue(interceptor.isActive)
    }

    func testClearingHistoryStopsLiveQueueWhenItRemovesTheFinalQueuedItem() {
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            liveQueuePasteInterceptor: interceptor
        )
        let item = makeTextItem("recent")
        store.insert(item)
        environment.togglePasteQueue(item)

        environment.clearHistory()

        XCTAssertTrue(environment.pasteQueue.isEmpty)
        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
    }

    func testCleanupStopsLiveQueueWhenTheFinalQueuedItemExpires() {
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            liveQueuePasteInterceptor: interceptor
        )
        let now = Date()
        let expired = makeTextItem(
            "expired",
            lastUsedAt: now.addingTimeInterval(-31 * 86_400)
        )
        store.insert(expired)
        environment.togglePasteQueue(expired)

        environment.runCleanup(now: now)

        XCTAssertTrue(environment.pasteQueue.isEmpty)
        XCTAssertFalse(environment.isLiveQueueActive)
        XCTAssertFalse(interceptor.isActive)
    }

    func testQueuedRestoreIsNotCapturedAgain() throws {
        let shortcuts = StubShortcutService()
        let interceptor = StubLiveQueuePasteInterceptor()
        environment = makeEnvironment(
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            liveQueuePasteInterceptor: interceptor
        )
        environment.start()
        pasteboard.stage(.text("queued"))
        environment.monitor.poll()
        let item = try XCTUnwrap(environment.items.first)
        environment.togglePasteQueue(item)

        interceptor.triggerCommandV()
        environment.monitor.poll()

        XCTAssertEqual(environment.items.count, 1)
        XCTAssertEqual(environment.captureCount, 1)
    }

    // MARK: - Pause

    func testPausingStopsTheMonitor() {
        environment.monitor.start()
        XCTAssertTrue(environment.monitor.isRunning)

        environment.toggleMonitoring()

        XCTAssertTrue(environment.isMonitoringPaused)
        XCTAssertFalse(environment.monitor.isRunning)
    }

    // MARK: - Capture signal

    /// `captureCount` is what drives the menu-bar confirmation. It must tick for
    /// anything recorded, and stay put for anything ignored.
    func testCaptureCountIncrementsForEachRecordedItem() {
        XCTAssertEqual(environment.captureCount, 0)

        pasteboard.stage(.text("one"))
        environment.monitor.poll()
        XCTAssertEqual(environment.captureCount, 1)

        pasteboard.stage(.text("two"))
        environment.monitor.poll()
        XCTAssertEqual(environment.captureCount, 2)
    }

    /// A repeated copy is still a capture from the user's point of view, so it
    /// should confirm rather than look like nothing happened.
    func testCaptureCountIncrementsForDuplicates() {
        pasteboard.stage(.text("repeated"))
        environment.monitor.poll()
        pasteboard.stage(.text("other"))
        environment.monitor.poll()
        pasteboard.stage(.text("repeated"))
        environment.monitor.poll()

        XCTAssertEqual(environment.captureCount, 3)
        XCTAssertEqual(environment.items.count, 2)
    }

    func testCaptureCountDoesNotMoveForIgnoredContent() {
        pasteboard.stageUnsupportedContent()
        environment.monitor.poll()

        XCTAssertEqual(environment.captureCount, 0)
    }

    func testRestoringDoesNotCountAsACapture() {
        pasteboard.stage(.text("only entry"))
        environment.monitor.poll()

        environment.restore(environment.items[0])
        environment.monitor.poll()

        XCTAssertEqual(environment.captureCount, 1)
    }

    // MARK: - Cleanup on capture

    func testCleanupRunsAfterEveryCapture() {
        environment.settingsStore.settings.maxItems = 2

        for index in 0..<5 {
            pasteboard.stage(.text("item-\(index)"))
            environment.monitor.poll()
        }

        XCTAssertEqual(environment.items.count, 2)
        XCTAssertEqual(environment.items.first?.textContent, "item-4")
    }

    private var store: any ClipboardStoring {
        environment.clipboardStore
    }
}
