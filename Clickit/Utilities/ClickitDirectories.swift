import Foundation

/// Every path Clickit writes to. All application data lives under a single
/// directory so that uninstalling is one `rm -rf`, and so no code has to
/// improvise a location.
enum ClickitDirectories {
    /// `~/Library/Application Support/Clickit`
    static func applicationSupport() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Clickit", isDirectory: true)
    }

    static func images() throws -> URL {
        try applicationSupport().appendingPathComponent("Images", isDirectory: true)
    }

    static func database() throws -> URL {
        try applicationSupport().appendingPathComponent("clickit.sqlite", isDirectory: false)
    }
}
