import Foundation

/// A single entry in the clipboard history.
///
/// This is a plain value type rather than a persistence-framework object. The
/// storage layer sits behind `ClipboardStoring`, so swapping the current
/// in-memory store for a disk-backed one (see ROADMAP phase 2) does not require
/// changing this model or any view that renders it.
///
/// Image bytes are never held here — only `imagePath`, a filename relative to
/// the Clickit image directory. See `ImageStorageService`.
struct ClipboardItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let type: ClipboardItemType
    let textContent: String?
    let imagePath: String?
    let contentHash: String
    let createdAt: Date
    var lastUsedAt: Date
    let sourceApplication: String?
    var isPinned: Bool
    let byteSize: Int

    init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        textContent: String? = nil,
        imagePath: String? = nil,
        contentHash: String,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        sourceApplication: String? = nil,
        isPinned: Bool = false,
        byteSize: Int
    ) {
        self.id = id
        self.type = type
        self.textContent = textContent
        self.imagePath = imagePath
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt ?? createdAt
        self.sourceApplication = sourceApplication
        self.isPinned = isPinned
        self.byteSize = byteSize
    }
}

extension ClipboardItem {
    /// Single-line summary shown in the history list. Newlines and runs of
    /// whitespace are collapsed so multi-line snippets stay one row tall.
    var previewText: String {
        switch type {
        case .text, .url:
            guard let textContent else { return type.displayName }
            let collapsed = textContent
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            return collapsed.isEmpty ? type.displayName : collapsed
        case .image:
            return "Image · \(FileSizeFormatter.string(fromByteCount: byteSize))"
        }
    }

    /// Text the search field matches against. Images are searchable by type
    /// name and source app only, since there is no OCR (and none is planned —
    /// it would mean shipping content analysis over private clipboard data).
    var searchableText: String {
        [textContent, sourceApplication, type.displayName]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    func matches(searchQuery: String) -> Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return searchableText.range(of: trimmed, options: .caseInsensitive) != nil
    }
}
