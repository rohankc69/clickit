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

    // MARK: - Pause

    func testPausingStopsTheMonitor() {
        environment.monitor.start()
        XCTAssertTrue(environment.monitor.isRunning)

        environment.toggleMonitoring()

        XCTAssertTrue(environment.isMonitoringPaused)
        XCTAssertFalse(environment.monitor.isRunning)
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
