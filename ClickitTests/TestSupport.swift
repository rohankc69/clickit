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

/// Accessibility state under the test's control, since a test process cannot
/// be granted or refused the real permission.
@MainActor
final class StubAccessibilityService: AccessibilityAuthorizing {
    var isTrusted: Bool
    private(set) var requestCount = 0

    init(isTrusted: Bool = false) {
        self.isTrusted = isTrusted
    }

    func requestAccess() {
        requestCount += 1
    }

    /// Mirrors the real reset: the record goes away, so the next request is
    /// treated as a first one.
    var resetSucceeds = true
    private(set) var resetCount = 0

    func resetAuthorization() -> Bool {
        resetCount += 1
        return resetSucceeds
    }
}

/// Login-item state under the test's control, since a test process cannot
/// register itself as a real login item.
@MainActor
final class StubLoginItemService: LoginItemManaging {
    var isEnabled: Bool
    /// When set, `setEnabled` throws instead of applying, standing in for macOS
    /// refusing to register an unverifiable bundle.
    var failure: Error?
    private(set) var setCalls: [Bool] = []

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        setCalls.append(enabled)
        if let failure { throw failure }
        isEnabled = enabled
    }
}

@MainActor
final class StubShortcutService: GlobalShortcutRegistering {
    var isSupported = true
    var registrationFailures: [GlobalShortcutAction: Error] = [:]
    private(set) var configurations: [GlobalShortcutAction: KeyboardShortcutConfiguration] = [:]
    private var handlers: [GlobalShortcutAction: @MainActor () -> Void] = [:]

    func register(
        _ configuration: KeyboardShortcutConfiguration,
        for action: GlobalShortcutAction,
        handler: @escaping @MainActor () -> Void
    ) throws {
        if let failure = registrationFailures[action] { throw failure }
        configurations[action] = configuration
        handlers[action] = handler
    }

    func unregister(_ action: GlobalShortcutAction) {
        configurations[action] = nil
        handlers[action] = nil
    }

    func unregisterAll() {
        configurations.removeAll()
        handlers.removeAll()
    }

    func trigger(_ action: GlobalShortcutAction) {
        handlers[action]?()
    }

}

@MainActor
final class StubLiveQueuePasteInterceptor: LiveQueuePasteIntercepting {
    private(set) var isActive = false
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0
    var activationError: Error?

    private var onCommandV: (@MainActor () -> Bool)?
    private var onFailure: (@MainActor (LiveQueuePasteInterceptorError) -> Void)?

    func activate(
        onCommandV: @escaping @MainActor () -> Bool,
        onFailure: @escaping @MainActor (LiveQueuePasteInterceptorError) -> Void
    ) throws {
        activationCount += 1
        if let activationError { throw activationError }
        self.onCommandV = onCommandV
        self.onFailure = onFailure
        isActive = true
    }

    func deactivate() {
        guard isActive else { return }
        deactivationCount += 1
        isActive = false
        onCommandV = nil
        onFailure = nil
    }

    @discardableResult
    func triggerCommandV() -> Bool? {
        let shouldContinue = onCommandV?()
        if shouldContinue == false {
            deactivate()
        }
        return shouldContinue
    }

    func triggerFailure(_ error: LiveQueuePasteInterceptorError = .disabled) {
        let handler = onFailure
        deactivate()
        handler?(error)
    }
}

@MainActor
final class StubScreenshotService: ScreenshotCapturing {
    private(set) var captureCount = 0
    private(set) var cancelCount = 0
    var failure: Error?
    var completionFailure: String?

    func captureSelectionToClipboard(
        onFailure: @escaping @MainActor @Sendable (String) -> Void
    ) throws {
        if let failure { throw failure }
        captureCount += 1
        if let completionFailure { onFailure(completionFailure) }
    }

    func cancel() {
        cancelCount += 1
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
        pasteboard: MockPasteboardService = MockPasteboardService(),
        shortcuts: GlobalShortcutRegistering = StubShortcutService(),
        liveQueuePasteInterceptor: LiveQueuePasteIntercepting = StubLiveQueuePasteInterceptor(),
        screenshots: ScreenshotCapturing = StubScreenshotService(),
        accessibility: AccessibilityAuthorizing = StubAccessibilityService(),
        loginItem: LoginItemManaging = StubLoginItemService()
    ) -> AppEnvironment {
        AppEnvironment(
            settingsStore: makeSettingsStore(settings),
            imageStorage: imageStorage,
            clipboardStore: makeStore(),
            pasteboard: pasteboard,
            shortcuts: shortcuts,
            liveQueuePasteInterceptor: liveQueuePasteInterceptor,
            screenshots: screenshots,
            accessibility: accessibility,
            loginItem: loginItem
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
