import Foundation

enum FileSizeFormatter {
    /// `FormatStyle` rather than a shared `ByteCountFormatter`: the style is a
    /// value type, so there is no cross-actor mutable state to guard.
    static func string(fromByteCount bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }

    static let megabyte = 1_024 * 1_024

    static func megabytes(_ count: Int) -> Int {
        count * megabyte
    }
}
