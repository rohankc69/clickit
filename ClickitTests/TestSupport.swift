import Foundation
import XCTest
@testable import Clickit

/// In-memory stand-in for `NSPasteboard`.
@MainActor
final class MockPasteboardService: PasteboardServicing {
    private(set) var changeCount = 0
    private(set) var writtenPayloads: [PasteboardPayload] = []

    private var snapshot: PasteboardSnapshot?

    /// Simulates another app putting something on the pasteboard.
    func stage(_ payload: PasteboardPayload, source: String? = "com.example.Editor") {
        snapshot = PasteboardSnapshot(payload: payload, sourceApplication: source)
        changeCount += 1
    }

    /// Simulates a change count bump with nothing Clickit can read.
    func stageUnsupportedContent() {
        snapshot = nil
        changeCount += 1
    }

    func read() -> PasteboardSnapshot? { snapshot }

    @discardableResult
    func write(_ payload: PasteboardPayload) -> Int {
        writtenPayloads.append(payload)
        snapshot = PasteboardSnapshot(payload: payload, sourceApplication: "com.clickit.Clickit")
        changeCount += 1
        return changeCount
    }
}

/// Base class that provides a scratch image directory and isolated defaults.
@MainActor
class ClickitTestCase: XCTestCase {
    private(set) var imageDirectory: URL!
    private(set) var imageStorage: ImageStorageService!
    private(set) var defaults: UserDefaults!
    private var suiteName: String!

    /// The `async` variants are used throughout rather than `setUpWithError`
    /// because only those can be actor-isolated, and this fixture hands out
    /// main-actor state.
    override func setUp() async throws {
        try await super.setUp()
        imageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClickitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        imageStorage = ImageStorageService(directory: imageDirectory)

        suiteName = "ClickitTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        if FileManager.default.fileExists(atPath: imageDirectory.path) {
            try FileManager.default.removeItem(at: imageDirectory)
        }
        // SQLite leaves -wal and -shm sidecars beside the database file.
        for suffix in ["", "-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try FileManager.default.removeItem(at: sidecar)
            }
        }
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    func makeSettingsStore(_ settings: ClickitSettings = .default) -> SettingsStore {
        let store = SettingsStore(defaults: defaults)
        store.settings = settings
        return store
    }

    func makeStore() -> InMemoryClipboardStore {
        InMemoryClipboardStore(imageStorage: imageStorage)
    }

    /// A database file inside this test's scratch directory. Calling
    /// `makeSQLiteStore()` more than once reopens the *same* file, which is how
    /// the durability tests simulate quitting and relaunching.
    var databaseURL: URL {
        imageDirectory.deletingLastPathComponent()
            .appendingPathComponent("\(imageDirectory.lastPathComponent).sqlite")
    }

    func makeSQLiteStore() throws -> SQLiteClipboardStore {
        try SQLiteClipboardStore(
            database: SQLiteDatabase(url: databaseURL),
            imageStorage: imageStorage
        )
    }

    func makeEnvironment(
        settings: ClickitSettings = .default,
        pasteboard: MockPasteboardService = MockPasteboardService()
    ) -> AppEnvironment {
        AppEnvironment(
            settingsStore: makeSettingsStore(settings),
            imageStorage: imageStorage,
            clipboardStore: makeStore(),
            pasteboard: pasteboard,
            shortcuts: ShortcutService()
        )
    }

    func makeTextItem(
        _ text: String,
        pinned: Bool = false,
        lastUsedAt: Date = Date()
    ) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            textContent: text,
            contentHash: ContentHasher.hash(text: text, type: .text),
            createdAt: lastUsedAt,
            lastUsedAt: lastUsedAt,
            isPinned: pinned,
            byteSize: text.utf8.count
        )
    }

    /// Writes real bytes to the scratch directory so file-deletion behaviour is
    /// exercised rather than mocked away.
    func makeImageItem(
        bytes: Int = 1_024,
        pinned: Bool = false,
        lastUsedAt: Date = Date()
    ) throws -> ClipboardItem {
        let data = Data(repeating: UInt8.random(in: 0...255), count: bytes)
        let path = try imageStorage.store(data: data)
        return ClipboardItem(
            type: .image,
            imagePath: path,
            contentHash: ContentHasher.hash(data: data, type: .image),
            createdAt: lastUsedAt,
            lastUsedAt: lastUsedAt,
            isPinned: pinned,
            byteSize: bytes
        )
    }

    func imageFileExists(_ item: ClipboardItem) throws -> Bool {
        let path = try XCTUnwrap(item.imagePath)
        return FileManager.default.fileExists(atPath: imageStorage.url(forRelativePath: path).path)
    }

    func daysAgo(_ days: Int, from reference: Date = Date()) -> Date {
        reference.addingTimeInterval(-Double(days) * 86_400)
    }
}
