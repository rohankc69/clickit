import XCTest
@testable import Clickit

/// The behaviour every `ClipboardStoring` implementation must exhibit.
///
/// Abstract: it defines the contract but does not run. Concrete suites below
/// supply a store and inherit every test, so the in-memory and SQLite stores
/// are held to exactly the same standard rather than drifting apart.
@MainActor
class ClipboardStoreContractTests: ClickitTestCase {
    /// Overridden by each concrete suite.
    func makeSubject() throws -> any ClipboardStoring {
        throw XCTSkip("abstract")
    }

    override class var defaultTestSuite: XCTestSuite {
        guard self != ClipboardStoreContractTests.self else {
            return XCTestSuite(name: "ClipboardStoreContractTests (abstract)")
        }
        return super.defaultTestSuite
    }

    // MARK: - Ordering

    func testInsertPutsNewestFirst() throws {
        let store = try makeSubject()
        store.insert(makeTextItem("first"))
        store.insert(makeTextItem("second"))

        XCTAssertEqual(store.items.map(\.textContent), ["second", "first"])
    }

    // MARK: - Duplicate handling

    func testDuplicateIsPromotedInsteadOfDuplicated() throws {
        let store = try makeSubject()
        let duplicate = makeTextItem("repeated")
        store.insert(duplicate)
        store.insert(makeTextItem("other"))

        let promoted = store.promoteDuplicate(contentHash: duplicate.contentHash, at: Date())

        XCTAssertTrue(promoted)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.textContent, "repeated")
    }

    func testPromoteReturnsFalseForUnknownContent() throws {
        let store = try makeSubject()
        store.insert(makeTextItem("only"))

        XCTAssertFalse(store.promoteDuplicate(contentHash: "not-a-real-hash", at: Date()))
        XCTAssertEqual(store.items.count, 1)
    }

    func testPromoteUpdatesLastUsedButKeepsCreatedAt() throws {
        let store = try makeSubject()
        let original = makeTextItem("kept", lastUsedAt: daysAgo(3))
        store.insert(original)

        let now = Date()
        store.promoteDuplicate(contentHash: original.contentHash, at: now)

        let stored = try XCTUnwrap(store.items.first)
        XCTAssertEqual(stored.lastUsedAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(stored.createdAt.timeIntervalSince1970, original.createdAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testMarkUsedMovesItemToTheFront() throws {
        let store = try makeSubject()
        let older = makeTextItem("older", lastUsedAt: daysAgo(2))
        store.insert(older)
        store.insert(makeTextItem("newer"))

        store.markUsed(id: older.id, at: Date())

        XCTAssertEqual(store.items.first?.id, older.id)
    }

    // MARK: - Pinning and deletion

    func testSetPinned() throws {
        let store = try makeSubject()
        let item = makeTextItem("pin me")
        store.insert(item)

        store.setPinned(true, id: item.id)
        XCTAssertEqual(store.items.first?.isPinned, true)

        store.setPinned(false, id: item.id)
        XCTAssertEqual(store.items.first?.isPinned, false)
    }

    func testDeletingImageRecordDeletesTheFileOnDisk() throws {
        let store = try makeSubject()
        let item = try makeImageItem()
        store.insert(item)
        XCTAssertTrue(try imageFileExists(item))

        store.delete(id: item.id)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(try imageFileExists(item))
    }

    func testDeletingSeveralItemsAtOnce() throws {
        let store = try makeSubject()
        let first = makeTextItem("one")
        let second = makeTextItem("two")
        let survivor = makeTextItem("three")
        [first, second, survivor].forEach(store.insert)

        store.delete(ids: [first.id, second.id])

        XCTAssertEqual(store.items.map(\.id), [survivor.id])
    }

    func testClearHistoryKeepsPinnedItemsAndTheirFiles() throws {
        let store = try makeSubject()
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
        let store = try makeSubject()
        let pinnedImage = try makeImageItem(pinned: true)
        store.insert(pinnedImage)
        store.insert(makeTextItem("text", pinned: true))

        store.deleteAll(includingPinned: true)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(try imageFileExists(pinnedImage))
    }

    // MARK: - Byte accounting

    func testTotalByteSizeSumsItems() throws {
        let store = try makeSubject()
        store.insert(try makeImageItem(bytes: 2_048))
        store.insert(makeTextItem("abcd"))

        XCTAssertEqual(store.totalByteSize, 2_052)
        XCTAssertEqual(store.imageByteSize, 2_048)
    }

    func testLoadImageDataRoundTrips() throws {
        let store = try makeSubject()
        let item = try makeImageItem(bytes: 64)
        store.insert(item)

        XCTAssertEqual(try store.loadImageData(for: item).count, 64)
    }

    func testLoadImageDataThrowsForTextItem() throws {
        let store = try makeSubject()
        let item = makeTextItem("no image here")
        store.insert(item)

        XCTAssertThrowsError(try store.loadImageData(for: item))
    }

    func testItemLookupByID() throws {
        let store = try makeSubject()
        let item = makeTextItem("findable")
        store.insert(item)

        XCTAssertEqual(store.item(id: item.id)?.textContent, "findable")
        XCTAssertNil(store.item(id: UUID()))
    }
}

/// The in-memory store, used as a fallback when the database cannot be opened.
@MainActor
final class InMemoryClipboardStoreTests: ClipboardStoreContractTests {
    override func makeSubject() throws -> any ClipboardStoring {
        makeStore()
    }
}

/// The disk-backed store, plus the durability behaviour that only it has.
@MainActor
final class SQLiteClipboardStoreTests: ClipboardStoreContractTests {
    override func makeSubject() throws -> any ClipboardStoring {
        try makeSQLiteStore()
    }

    // MARK: - Durability

    func testHistorySurvivesReopeningTheDatabase() throws {
        let first = try makeSQLiteStore()
        first.insert(makeTextItem("written before quitting"))
        first.insert(makeTextItem("second entry"))

        let reopened = try makeSQLiteStore()

        XCTAssertEqual(reopened.items.map(\.textContent), ["second entry", "written before quitting"])
    }

    func testEveryFieldSurvivesAReopen() throws {
        let original = ClipboardItem(
            type: .url,
            textContent: "https://example.com/page",
            contentHash: "hash-of-the-link",
            createdAt: daysAgo(4),
            lastUsedAt: daysAgo(1),
            sourceApplication: "com.example.Browser",
            isPinned: true,
            byteSize: 24
        )
        let first = try makeSQLiteStore()
        first.insert(original)

        let restored = try XCTUnwrap(try makeSQLiteStore().items.first)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.type, .url)
        XCTAssertEqual(restored.textContent, original.textContent)
        XCTAssertEqual(restored.contentHash, original.contentHash)
        XCTAssertEqual(restored.sourceApplication, "com.example.Browser")
        XCTAssertTrue(restored.isPinned)
        XCTAssertEqual(restored.byteSize, 24)
        XCTAssertEqual(restored.createdAt.timeIntervalSince1970, original.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(restored.lastUsedAt.timeIntervalSince1970, original.lastUsedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testImagePathSurvivesAReopenAndTheFileIsStillReadable() throws {
        let first = try makeSQLiteStore()
        let item = try makeImageItem(bytes: 128)
        first.insert(item)

        let reopened = try makeSQLiteStore()
        let restored = try XCTUnwrap(reopened.items.first)

        XCTAssertEqual(restored.imagePath, item.imagePath)
        XCTAssertEqual(try reopened.loadImageData(for: restored).count, 128)
    }

    func testDeletionsSurviveAReopen() throws {
        let first = try makeSQLiteStore()
        let doomed = makeTextItem("delete me")
        first.insert(doomed)
        first.insert(makeTextItem("keep me"))
        first.delete(id: doomed.id)

        XCTAssertEqual(try makeSQLiteStore().items.map(\.textContent), ["keep me"])
    }

    func testPinStateSurvivesAReopen() throws {
        let first = try makeSQLiteStore()
        let item = makeTextItem("pinned across launches")
        first.insert(item)
        first.setPinned(true, id: item.id)

        XCTAssertEqual(try makeSQLiteStore().items.first?.isPinned, true)
    }

    func testItemsLoadMostRecentlyUsedFirst() throws {
        let first = try makeSQLiteStore()
        first.insert(makeTextItem("middle", lastUsedAt: daysAgo(2)))
        first.insert(makeTextItem("oldest", lastUsedAt: daysAgo(9)))
        first.insert(makeTextItem("newest", lastUsedAt: daysAgo(1)))

        XCTAssertEqual(try makeSQLiteStore().items.map(\.textContent), ["newest", "middle", "oldest"])
    }

    // MARK: - Housekeeping

    /// Files left behind by a delete that was interrupted between removing the
    /// row and unlinking the file are cleaned up on the next launch.
    func testOrphanedImageFilesAreRemovedOnOpen() throws {
        let first = try makeSQLiteStore()
        let referenced = try makeImageItem(bytes: 16)
        first.insert(referenced)

        // Stranded after the store was already open, so it survives until the
        // next launch reconciles.
        let orphanPath = try imageStorage.store(data: Data(repeating: 0x5A, count: 32))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageStorage.url(forRelativePath: orphanPath).path))

        _ = try makeSQLiteStore()

        XCTAssertFalse(FileManager.default.fileExists(atPath: imageStorage.url(forRelativePath: orphanPath).path))
        XCTAssertTrue(try imageFileExists(referenced))
    }

    func testSchemaVersionIsRecorded() throws {
        _ = try makeSQLiteStore()
        let database = try SQLiteDatabase(url: databaseURL)

        XCTAssertEqual(try database.userVersion, 1)
    }

    /// Re-opening an existing database must not re-run migrations destructively.
    func testReopeningAnExistingDatabaseKeepsData() throws {
        let first = try makeSQLiteStore()
        first.insert(makeTextItem("survives migration check"))

        _ = try makeSQLiteStore()
        let third = try makeSQLiteStore()

        XCTAssertEqual(third.items.count, 1)
    }

    /// The unique index on `content_hash` is a second line of defence behind
    /// the capture path's duplicate check.
    func testDuplicateHashIsRejectedByTheSchema() throws {
        let store = try makeSQLiteStore()
        let item = makeTextItem("only once")
        store.insert(item)

        var reportedError: Error?
        let strict = try SQLiteClipboardStore(
            database: SQLiteDatabase(url: databaseURL),
            imageStorage: imageStorage,
            onError: { reportedError = $0 }
        )
        strict.insert(makeTextItem("only once"))

        XCTAssertNotNil(reportedError, "a colliding hash should surface an error rather than being dropped")
        XCTAssertEqual(try makeSQLiteStore().items.count, 1)
    }
}
