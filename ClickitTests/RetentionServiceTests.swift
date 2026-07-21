import XCTest
@testable import Clickit

@MainActor
final class RetentionServiceTests: ClickitTestCase {
    private let retention = RetentionService()

    // MARK: - Expiry

    func testExpiredTextIsRemoved() {
        let store = makeStore()
        store.insert(makeTextItem("stale", lastUsedAt: daysAgo(31)))
        store.insert(makeTextItem("fresh", lastUsedAt: daysAgo(29)))

        let report = retention.runCleanup(store: store, settings: .default)

        XCTAssertEqual(report.expired, 1)
        XCTAssertEqual(store.items.map(\.textContent), ["fresh"])
    }

    /// Images use the shorter window, so a 10-day-old image expires while a
    /// 10-day-old note does not.
    func testImagesExpireOnTheirOwnShorterSchedule() throws {
        let store = makeStore()
        let oldImage = try makeImageItem(lastUsedAt: daysAgo(10))
        store.insert(oldImage)
        store.insert(makeTextItem("same age", lastUsedAt: daysAgo(10)))

        let report = retention.runCleanup(store: store, settings: .default)

        XCTAssertEqual(report.expired, 1)
        XCTAssertEqual(store.items.map(\.type), [.text])
        XCTAssertFalse(try imageFileExists(oldImage))
    }

    func testPinnedItemsNeverExpire() throws {
        let store = makeStore()
        let ancientImage = try makeImageItem(pinned: true, lastUsedAt: daysAgo(400))
        store.insert(ancientImage)
        store.insert(makeTextItem("ancient", pinned: true, lastUsedAt: daysAgo(400)))

        let report = retention.runCleanup(store: store, settings: .default)

        XCTAssertEqual(report.expired, 0)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertTrue(try imageFileExists(ancientImage))
    }

    /// Recency is measured from `lastUsedAt`, so re-using an old entry keeps it.
    func testReusingAnOldItemResetsItsClock() {
        let store = makeStore()
        let old = makeTextItem("revived", lastUsedAt: daysAgo(60))
        store.insert(old)
        store.promoteDuplicate(contentHash: old.contentHash, at: Date())

        let report = retention.runCleanup(store: store, settings: .default)

        XCTAssertEqual(report.expired, 0)
        XCTAssertEqual(store.items.count, 1)
    }

    // MARK: - Item count limit

    func testOldestUnpinnedItemsAreTrimmedOverTheCountLimit() {
        var settings = ClickitSettings.default
        settings.maxItems = 3

        let store = makeStore()
        for index in 0..<6 {
            // index 0 is the oldest.
            store.insert(makeTextItem("item-\(index)", lastUsedAt: daysAgo(6 - index)))
        }

        let report = retention.runCleanup(store: store, settings: settings)

        XCTAssertEqual(report.overItemLimit, 3)
        XCTAssertEqual(store.items.map(\.textContent), ["item-5", "item-4", "item-3"])
    }

    func testCountTrimSkipsPinnedItems() {
        var settings = ClickitSettings.default
        settings.maxItems = 2

        let store = makeStore()
        store.insert(makeTextItem("pinned-oldest", pinned: true, lastUsedAt: daysAgo(5)))
        store.insert(makeTextItem("middle", lastUsedAt: daysAgo(4)))
        store.insert(makeTextItem("newest", lastUsedAt: daysAgo(3)))

        let report = retention.runCleanup(store: store, settings: settings)

        XCTAssertEqual(report.overItemLimit, 1)
        XCTAssertEqual(
            Set(store.items.compactMap(\.textContent)),
            ["pinned-oldest", "newest"]
        )
    }

    func testNoTrimWhenUnderTheLimit() {
        let store = makeStore()
        store.insert(makeTextItem("only"))

        XCTAssertTrue(retention.runCleanup(store: store, settings: .default).isEmpty)
        XCTAssertEqual(store.items.count, 1)
    }

    // MARK: - Storage size limit

    func testOldestImagesAreEvictedOverTheSizeLimit() throws {
        var settings = ClickitSettings.default
        settings.maxStorageBytes = 2_500

        let store = makeStore()
        let oldest = try makeImageItem(bytes: 1_000, lastUsedAt: daysAgo(3))
        let middle = try makeImageItem(bytes: 1_000, lastUsedAt: daysAgo(2))
        let newest = try makeImageItem(bytes: 1_000, lastUsedAt: daysAgo(1))
        [oldest, middle, newest].forEach(store.insert)

        let report = retention.runCleanup(store: store, settings: settings)

        XCTAssertEqual(report.overSizeLimit, 1)
        XCTAssertEqual(Set(store.items.map(\.id)), [middle.id, newest.id])
        XCTAssertFalse(try imageFileExists(oldest))
        XCTAssertTrue(try imageFileExists(middle))
    }

    func testSizeTrimNeverEvictsPinnedImages() throws {
        var settings = ClickitSettings.default
        settings.maxStorageBytes = 1_500

        let store = makeStore()
        let pinnedOld = try makeImageItem(bytes: 1_000, pinned: true, lastUsedAt: daysAgo(9))
        let loose = try makeImageItem(bytes: 1_000, lastUsedAt: daysAgo(1))
        store.insert(pinnedOld)
        store.insert(loose)

        let report = retention.runCleanup(store: store, settings: settings)

        XCTAssertEqual(report.overSizeLimit, 1)
        XCTAssertEqual(store.items.map(\.id), [pinnedOld.id])
        XCTAssertTrue(try imageFileExists(pinnedOld))
        XCTAssertFalse(try imageFileExists(loose))
    }

    /// Text is never dropped to satisfy a byte budget; with no image candidates
    /// left the pass simply stops rather than looping or deleting notes.
    func testSizeTrimStopsWhenOnlyTextRemains() {
        var settings = ClickitSettings.default
        settings.maxStorageBytes = 4

        let store = makeStore()
        store.insert(makeTextItem("a longer piece of text"))

        let report = retention.runCleanup(store: store, settings: settings)

        XCTAssertEqual(report.overSizeLimit, 0)
        XCTAssertEqual(store.items.count, 1)
    }

    func testCleanupIsIdempotent() throws {
        var settings = ClickitSettings.default
        settings.maxItems = 2

        let store = makeStore()
        store.insert(try makeImageItem(bytes: 100, lastUsedAt: daysAgo(20)))
        for index in 0..<4 {
            store.insert(makeTextItem("t\(index)", lastUsedAt: daysAgo(4 - index)))
        }

        let first = retention.runCleanup(store: store, settings: settings)
        let second = retention.runCleanup(store: store, settings: settings)

        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(store.items.count, 2)
    }
}
