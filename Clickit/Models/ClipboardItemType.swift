import Foundation

/// The kinds of clipboard content Clickit understands.
///
/// `rawValue` is persisted and folded into content hashes, so existing cases
/// must keep their spelling once a release ships.
enum ClipboardItemType: String, Codable, CaseIterable, Sendable {
    case text
    case url
    case image

    var systemImageName: String {
        switch self {
        case .text: "text.alignleft"
        case .url: "link"
        case .image: "photo"
        }
    }

    var displayName: String {
        switch self {
        case .text: "Text"
        case .url: "Link"
        case .image: "Image"
        }
    }

    /// Images and screenshots expire on their own, shorter schedule because they
    /// are both the largest items and the most likely to contain something the
    /// user did not mean to keep.
    var usesImageRetentionPolicy: Bool {
        self == .image
    }
}
