import XCTest
@testable import Clickit

@MainActor
final class ClipboardStoreTests: ClickitTestCase {
    func testInsertPutsNewestFirst() {
        let store = makeStore()
        store.insert(makeTextItem("first"))
        store.insert(makeTextItem("second"))

        XCTAssertEqual(store.items.map(\.textContent), ["second", "first"])
    }

    // MARK: - Duplicate handling

    func testDuplicateIsPromotedInsteadOfDuplicated() {
        let store = makeStore()
        let duplicate = makeTextItem("repeated")
        store.insert(duplicate)
        store.insert(makeTextItem("other"))

        let promoted = store.promoteDuplicate(contentHash: duplicate.contentHash, at: Date())

        XCTAssertTrue(promoted)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.textContent, "repeated")
    }

    func testPromoteReturnsFalseForUnknownContent() {
        let store = makeStore()
        store.insert(makeTextItem("only"))

        XCTAssertFalse(store.promoteDuplicate(contentHash: "not-a-real-hash", at: Date()))
        XCTAssertEqual(store.items.count, 1)
    }

    func testPromoteUpdatesLastUsedButKeepsCreatedAt() {
        let store = makeStore()
        let original = makeTextItem("kept", lastUsedAt: daysAgo(3))
        store.insert(original)

        let now = Date()
        store.promoteDuplicate(contentHash: original.contentHash, at: now)

        let stored = try? XCTUnwrap(store.items.first)
        XCTAssertEqual(stored?.lastUsedAt, now)
        XCTAssertEqual(stored?.createdAt, original.createdAt)
    }

    // MARK: - Pinning and deletion

    func testSetPinned() {
        let store = makeStore()
        let item = makeTextItem("pin me")
        store.insert(item)

        store.setPinned(true, id: item.id)
        XCTAssertEqual(store.items.first?.isPinned, true)

        store.setPinned(false, id: item.id)
        XCTAssertEqual(store.items.first?.isPinned, false)
    }

    func testDeletingImageRecordDeletesTheFileOnDisk() throws {
        let store = makeStore()
        let item = try makeImageItem()
        store.insert(item)
        XCTAssertTrue(try imageFileExists(item))

        store.delete(id: item.id)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(try imageFileExists(item))
    }

    func testClearHistoryKeepsPinnedItemsAndTheirFiles() throws {
        let store = makeStore()
        let pinnedImage = try makeImageItem(pinned: true)
        let looseImage = try makeImageItem()
        store.insert(pinnedImage)
        store.insert(looseImage)
        store.insert(makeTextItem("loose text"))

        store.deleteAll(includingPinned: false)

        XCTAssertEqual(store.items.map(\.id), [pinnedImage.id])
        XCTAssertTrue(try imageFileExists(pinnedImage))
        XCTAssertFalse(try imageFileExists(looseImage))
    }

    func testDeleteAllIncludingPinnedRemovesEverything() throws {
        let store = makeStore()
        let pinnedImage = try makeImageItem(pinned: true)
        store.insert(pinnedImage)
        store.insert(makeTextItem("text", pinned: true))

        store.deleteAll(includingPinned: true)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(try imageFileExists(pinnedImage))
    }

    // MARK: - Byte accounting

    func testTotalByteSizeSumsItems() throws {
        let store = makeStore()
        store.insert(try makeImageItem(bytes: 2_048))
        store.insert(makeTextItem("abcd"))

        XCTAssertEqual(store.totalByteSize, 2_052)
        XCTAssertEqual(store.imageByteSize, 2_048)
    }

    func testLoadImageDataRoundTrips() throws {
        let store = makeStore()
        let item = try makeImageItem(bytes: 64)
        store.insert(item)

        XCTAssertEqual(try store.loadImageData(for: item).count, 64)
    }

    func testLoadImageDataThrowsForTextItem() {
        let store = makeStore()
        let item = makeTextItem("no image here")
        store.insert(item)

        XCTAssertThrowsError(try store.loadImageData(for: item))
    }
}
