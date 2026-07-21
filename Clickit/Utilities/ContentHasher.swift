import CryptoKit
import Foundation

/// Produces the stable fingerprint used for duplicate detection.
///
/// The type is folded into the digest so that, for example, the string
/// "https://example.com" captured as `.url` and the same string captured as
/// `.text` never collide into a single history entry.
enum ContentHasher {
    static func hash(data: Data, type: ClipboardItemType) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(type.rawValue.utf8))
        hasher.update(data: Data([0x00]))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func hash(text: String, type: ClipboardItemType) -> String {
        hash(data: Data(text.utf8), type: type)
    }
}
