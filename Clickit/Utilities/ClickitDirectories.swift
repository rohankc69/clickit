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
        let directory = base.appendingPathComponent("Clickit", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromBackup(directory)
        return directory
    }

    /// Keeps clipboard history out of Time Machine and any other backup that
    /// honours the standard resource value.
    ///
    /// History routinely contains passwords and private messages, and a backup
    /// can end up on an external drive or a network destination the user never
    /// intended to copy it to. Failure to set the flag is logged but not fatal:
    /// losing backup exclusion is better than refusing to launch.
    static func excludeFromBackup(_ directory: URL) {
        var directory = directory
        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        } catch {
            ClickitLog.storage.error(
                "Could not exclude the Clickit data directory from backups: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    static func images() throws -> URL {
        try applicationSupport().appendingPathComponent("Images", isDirectory: true)
    }

    static func database() throws -> URL {
        try applicationSupport().appendingPathComponent("clickit.sqlite", isDirectory: false)
    }
}
