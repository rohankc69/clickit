import Foundation
import OSLog

/// Central log handles. Clickit never logs clipboard *contents* — only metadata
/// such as type, size and hashes — because the log stream is readable by other
/// processes and clipboard history routinely contains secrets.
enum ClickitLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.clickit.Clickit"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let retention = Logger(subsystem: subsystem, category: "retention")
    static let shortcut = Logger(subsystem: subsystem, category: "shortcut")
}
