import Foundation
import Observation

/// Disk-backed history, conforming to the same `ClipboardStoring` protocol as
/// the in-memory store.
///
/// The item list is held as a **write-through cache**: reads come from memory,
/// every mutation updates the array and the database together, and the array is
/// loaded from the database at launch. This is what lets search, retention and
/// the views stay synchronous — `items` is a plain array, exactly as before —
/// while still surviving a quit.
///
/// The cache is affordable because history is bounded (1,000 items by default)
/// and image bytes are never in it; only filenames are.
@MainActor
@Observable
final class SQLiteClipboardStore: ClipboardStoring {
    private(set) var items: [ClipboardItem] = []

    @ObservationIgnored private let database: SQLiteDatabase
    @ObservationIgnored private let imageStorage: ImageStoring
    /// Writes cannot throw through `ClipboardStoring`, so failures are reported
    /// here instead of being dropped. `AppEnvironment` surfaces them in the UI.
    @ObservationIgnored private let onError: (Error) -> Void

    init(
        database: SQLiteDatabase,
        imageStorage: ImageStoring,
        onError: @escaping (Error) -> Void = { _ in }
    ) throws {
        self.database = database
        self.imageStorage = imageStorage
        self.onError = onError

        try Self.migrate(database)
        items = try Self.loadAll(from: database)
        reconcileOrphanedImageFiles()
    }

    convenience init(
        imageStorage: ImageStoring,
        onError: @escaping (Error) -> Void = { _ in }
    ) throws {
        let url = try ClickitDirectories.database()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try self.init(database: SQLiteDatabase(url: url), imageStorage: imageStorage, onError: onError)
    }

    // MARK: - Schema

    private static let latestSchemaVersion: Int32 = 1

    /// Migrations run in order and are keyed off `PRAGMA user_version`. Adding a
    /// version means appending a case, never editing an existing one.
    private static func migrate(_ database: SQLiteDatabase) throws {
        let currentVersion = try database.userVersion
        guard currentVersion < latestSchemaVersion else { return }

        if currentVersion < 1 {
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS items (
                    id TEXT PRIMARY KEY NOT NULL,
                    type TEXT NOT NULL,
                    text_content TEXT,
                    image_path TEXT,
                    content_hash TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    last_used_at REAL NOT NULL,
                    source_application TEXT,
                    is_pinned INTEGER NOT NULL DEFAULT 0,
                    byte_size INTEGER NOT NULL
                )
                """
            )
            // Duplicate prevention is enforced by the schema, not only by the
            // capture path, so a bug upstream cannot corrupt the history.
            try database.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_items_hash ON items(content_hash)")
            try database.execute("CREATE INDEX IF NOT EXISTS idx_items_last_used ON items(last_used_at DESC)")
        }

        try database.setUserVersion(latestSchemaVersion)
    }

    private static let selectColumns =
        "id, type, text_content, image_path, content_hash, created_at, last_used_at, source_application, is_pinned, byte_size"

    private static func loadAll(from database: SQLiteDatabase) throws -> [ClipboardItem] {
        try database
            .query("SELECT \(selectColumns) FROM items ORDER BY last_used_at DESC") { row -> ClipboardItem? in
                guard let idString = row.string(0), let id = UUID(uuidString: idString),
                      let typeString = row.string(1), let type = ClipboardItemType(rawValue: typeString),
                      let contentHash = row.string(4)
                else { return nil }

                return ClipboardItem(
                    id: id,
                    type: type,
                    textContent: row.string(2),
                    imagePath: row.string(3),
                    contentHash: contentHash,
                    createdAt: Date(timeIntervalSince1970: row.double(5)),
                    lastUsedAt: Date(timeIntervalSince1970: row.double(6)),
                    sourceApplication: row.string(7),
                    isPinned: row.bool(8),
                    byteSize: row.int(9)
                )
            }
            // A row that cannot be decoded is skipped rather than aborting the
            // whole load, so one bad record never costs the user their history.
            .compactMap { $0 }
    }

    /// Deletes image files with no surviving record. These accumulate when a
    /// delete is interrupted between removing the row and unlinking the file.
    private func reconcileOrphanedImageFiles() {
        let referenced = Set(items.compactMap(\.imagePath))
        do {
            let orphans = try imageStorage.storedFilenames().filter { !referenced.contains($0) }
            guard !orphans.isEmpty else { return }

            for orphan in orphans {
                try? imageStorage.delete(relativePath: orphan)
            }
            ClickitLog.storage.info("Removed \(orphans.count, privacy: .public) orphaned image files")
        } catch {
            ClickitLog.storage.error(
                "Could not reconcile image files: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Reads

    func item(id: UUID) -> ClipboardItem? {
        items.first { $0.id == id }
    }

    func loadImageData(for item: ClipboardItem) throws -> Data {
        guard let imagePath = item.imagePath else {
            throw ImageStorageError.missingFile(path: "<none>")
        }
        return try imageStorage.loadData(relativePath: imagePath)
    }

    // MARK: - Writes

    func insert(_ item: ClipboardItem) {
        write {
            try database.execute(
                """
                INSERT INTO items (\(Self.selectColumns))
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(item.id.uuidString),
                    .text(item.type.rawValue),
                    .text(item.textContent),
                    .text(item.imagePath),
                    .text(item.contentHash),
                    .double(item.createdAt.timeIntervalSince1970),
                    .double(item.lastUsedAt.timeIntervalSince1970),
                    .text(item.sourceApplication),
                    .int(item.isPinned ? 1 : 0),
                    .int(item.byteSize),
                ]
            )
            items.insert(item, at: 0)
        }
    }

    @discardableResult
    func promoteDuplicate(contentHash: String, at date: Date) -> Bool {
        guard let index = items.firstIndex(where: { $0.contentHash == contentHash }) else {
            return false
        }
        var existing = items[index]
        existing.lastUsedAt = date

        write {
            try database.execute(
                "UPDATE items SET last_used_at = ? WHERE id = ?",
                [.double(date.timeIntervalSince1970), .text(existing.id.uuidString)]
            )
            items.remove(at: index)
            items.insert(existing, at: 0)
        }
        return true
    }

    func markUsed(id: UUID, at date: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        item.lastUsedAt = date

        write {
            try database.execute(
                "UPDATE items SET last_used_at = ? WHERE id = ?",
                [.double(date.timeIntervalSince1970), .text(id.uuidString)]
            )
            items.remove(at: index)
            items.insert(item, at: 0)
        }
    }

    func setPinned(_ isPinned: Bool, id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        write {
            try database.execute(
                "UPDATE items SET is_pinned = ? WHERE id = ?",
                [.int(isPinned ? 1 : 0), .text(id.uuidString)]
            )
            items[index].isPinned = isPinned
        }
    }

    func delete(ids: [UUID]) {
        let doomed = Set(ids)
        guard !doomed.isEmpty else { return }
        let removed = items.filter { doomed.contains($0.id) }
        guard !removed.isEmpty else { return }

        write {
            try database.transaction {
                for id in doomed {
                    try database.execute("DELETE FROM items WHERE id = ?", [.text(id.uuidString)])
                }
            }
            items.removeAll { doomed.contains($0.id) }
        }
        removed.forEach(discardImageFile)
    }

    func deleteAll(includingPinned: Bool) {
        let removed = includingPinned ? items : items.filter { !$0.isPinned }
        guard !removed.isEmpty else { return }

        write {
            try database.execute(includingPinned ? "DELETE FROM items" : "DELETE FROM items WHERE is_pinned = 0")
            items = includingPinned ? [] : items.filter(\.isPinned)
        }
        removed.forEach(discardImageFile)
    }

    /// Applies a database change and its cache update together. If the write
    /// fails the cache is left untouched, so memory never claims something the
    /// database does not hold.
    private func write(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            ClickitLog.storage.error("Database write failed: \(error.localizedDescription, privacy: .public)")
            onError(error)
        }
    }

    private func discardImageFile(for item: ClipboardItem) {
        guard let imagePath = item.imagePath else { return }
        do {
            try imageStorage.delete(relativePath: imagePath)
        } catch {
            ClickitLog.storage.error(
                "Failed to delete image file: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
