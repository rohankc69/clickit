import XCTest
@testable import Clickit

/// The data directory holds clipboard history, so its backup treatment is
/// verified against a scratch directory rather than the real Application
/// Support location.
@MainActor
final class ClickitDirectoriesTests: ClickitTestCase {
    func testDataDirectoryIsExcludedFromBackups() throws {
        let directory = imageDirectory.appendingPathComponent("Clickit", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        ClickitDirectories.excludeFromBackup(directory)

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
}
