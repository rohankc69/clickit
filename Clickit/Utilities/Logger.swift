import Foundation
import OSLog

/// Central log handles. Clickit never logs clipboard *contents* — only metadata
/// such as type, size and hashes — because the log stream is readable by other
/// processes and clipboard history routinely contains secrets.
///
/// Levels are chosen for what survives to disk, not for how interesting a line
/// looks while developing:
///
/// - `notice` for anything a bug report might turn on. macOS persists it, so it
///   is still there when a user reports the problem hours later.
/// - `info` for running commentary. It lives in a memory buffer and is gone
///   within minutes, so nothing that explains a failure belongs here.
/// - `error` for failures.
///
/// The distinction is not cosmetic. Diagnosing a permission problem in this app
/// once required inferring state from stored settings, because every line that
/// would have answered it had been logged at `info` and had already evaporated.
enum ClickitLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.clickit.Clickit"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let retention = Logger(subsystem: subsystem, category: "retention")
    static let shortcut = Logger(subsystem: subsystem, category: "shortcut")
}
