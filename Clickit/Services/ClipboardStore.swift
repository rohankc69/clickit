import Foundation
import Observation

/// The history collection.
///
/// `items` is always ordered most-recently-used first, with pinned entries left
/// in place rather than hoisted — retention rules walk this order to find the
/// oldest candidates, and the *view* is what groups pins to the top. Keeping
/// the two concerns apart means cleanup logic never has to reason about pins
/// except to skip them.
@MainActor
protocol ClipboardStoring: AnyObject {
    var items: [ClipboardItem] { get }

    func item(id: UUID) -> ClipboardItem?

    /// Moves an existing entry with the same fingerprint to the front rather
    /// than recording a second identical row. Returns `false` when the
    /// fingerprint is new.
    @discardableResult
    func promoteDuplicate(contentHash: String, at date: Date) -> Bool

    func insert(_ item: ClipboardItem)
    func markUsed(id: UUID, at date: Date)
    func setPinned(_ isPinned: Bool, id: UUID)

    /// Removes records and any image files they own.
    func delete(ids: [UUID])
    func deleteAll(includingPinned: Bool)

    func loadImageData(for item: ClipboardItem) throws -> Data
}

extension ClipboardStoring {
    func delete(id: UUID) {
        delete(ids: [id])
    }

    var totalByteSize: Int {
        items.reduce(0) { $0 + $1.byteSize }
    }

    var imageByteSize: Int {
        items.filter { $0.type == .image }.reduce(0) { $0 + $1.byteSize }
    }
}

/// In-memory implementation used by the current milestone.
///
/// History does not survive quitting. A disk-backed store is roadmap phase 2
/// and will conform to this same protocol; nothing above this line should need
/// to change when it lands.
@MainActor
@Observable
final class InMemoryClipboardStore: ClipboardStoring {
    private(set) var items: [ClipboardItem] = []

    private let imageStorage: ImageStoring

    init(imageStorage: ImageStoring) {
        self.imageStorage = imageStorage
    }

    func item(id: UUID) -> ClipboardItem? {
        items.first { $0.id == id }
    }

    @discardableResult
    func promoteDuplicate(contentHash: String, at date: Date) -> Bool {
        guard let index = items.firstIndex(where: { $0.contentHash == contentHash }) else {
            return false
        }
        var existing = items.remove(at: index)
        existing.lastUsedAt = date
        items.insert(existing, at: 0)
        return true
    }

    func insert(_ item: ClipboardItem) {
        items.insert(item, at: 0)
    }

    func markUsed(id: UUID, at date: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.lastUsedAt = date
        items.insert(item, at: 0)
    }

    func setPinned(_ isPinned: Bool, id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned = isPinned
    }

    func delete(ids: [UUID]) {
        let doomed = Set(ids)
        guard !doomed.isEmpty else { return }
        let removed = items.filter { doomed.contains($0.id) }
        items.removeAll { doomed.contains($0.id) }
        removed.forEach(discardImageFile)
    }

    func deleteAll(includingPinned: Bool) {
        let removed = includingPinned ? items : items.filter { !$0.isPinned }
        items = includingPinned ? [] : items.filter(\.isPinned)
        removed.forEach(discardImageFile)
    }

    func loadImageData(for item: ClipboardItem) throws -> Data {
        guard let imagePath = item.imagePath else {
            throw ImageStorageError.missingFile(path: "<none>")
        }
        return try imageStorage.loadData(relativePath: imagePath)
    }

    /// A failed unlink leaves an orphaned file but must not take the record
    /// removal down with it, so it is logged rather than propagated.
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
