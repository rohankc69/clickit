import XCTest
@testable import Clickit

/// Boot time is injected so a restart can be simulated without one.
private struct StubBootTimeProvider: BootTimeProviding {
    var bootTime: Date?
}

@MainActor
final class SessionResetServiceTests: ClickitTestCase {
    private let firstBoot = Date(timeIntervalSince1970: 1_000_000)
    private let secondBoot = Date(timeIntervalSince1970: 2_000_000)

    private func makeService(bootTime: Date?) -> SessionResetService {
        SessionResetService(bootTimeProvider: StubBootTimeProvider(bootTime: bootTime), defaults: defaults)
    }

    /// The very first launch has no recorded boot time; adopting it silently is
    /// correct, since there is no history to have accumulated yet.
    func testFirstEverLaunchDoesNotClear() {
        let store = makeStore()
        store.insert(makeTextItem("existing"))

        let cleared = makeService(bootTime: firstBoot)
            .resetIfSystemRestarted(store: store, settings: .default)

        XCTAssertFalse(cleared)
        XCTAssertEqual(store.items.count, 1)
    }

    func testRelaunchingWithinTheSameSessionKeepsHistory() {
        let store = makeStore()
        makeService(bootTime: firstBoot).resetIfSystemRestarted(store: store, settings: .default)
        store.insert(makeTextItem("copied this session"))

        let cleared = makeService(bootTime: firstBoot)
            .resetIfSystemRestarted(store: store, settings: .default)

        XCTAssertFalse(cleared)
        XCTAssertEqual(store.items.count, 1)
    }

    func testRestartClearsUnpinnedHistory() {
        let store = makeStore()
        makeService(bootTime: firstBoot).resetIfSystemRestarted(store: store, settings: .default)
        store.insert(makeTextItem("from before the restart"))

        let cleared = makeService(bootTime: secondBoot)
            .resetIfSystemRestarted(store: store, settings: .default)

        XCTAssertTrue(cleared)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testRestartKeepsPinnedItemsAndTheirFiles() throws {
        let store = makeStore()
        makeService(bootTime: firstBoot).resetIfSystemRestarted(store: store, settings: .default)
        let pinnedImage = try makeImageItem(pinned: true)
        store.insert(pinnedImage)
        store.insert(makeTextItem("pinned note", pinned: true))
        store.insert(makeTextItem("disposable"))

        makeService(bootTime: secondBoot).resetIfSystemRestarted(store: store, settings: .default)

        XCTAssertEqual(store.items.count, 2)
        XCTAssertTrue(store.items.allSatisfy(\.isPinned))
        XCTAssertTrue(try imageFileExists(pinnedImage))
    }

    func testRestartDeletesImageFilesOfUnpinnedItems() throws {
        let store = makeStore()
        makeService(bootTime: firstBoot).resetIfSystemRestarted(store: store, settings: .default)
        let screenshot = try makeImageItem()
        store.insert(screenshot)

        makeService(bootTime: secondBoot).resetIfSystemRestarted(store: store, settings: .default)

        XCTAssertFalse(try imageFileExists(screenshot))
    }

    func testDisablingTheBehaviourKeepsHistoryAcrossARestart() {
        var settings = ClickitSettings.default
        settings.clearHistoryOnRestart = false

        let store = makeStore()
        makeService(bootTime: firstBoot).resetIfSystemRestarted(store: store, settings: settings)
        store.insert(makeTextItem("kept deliberately"))

        let cleared = makeService(bootTime: secondBoot)
            .resetIfSystemRestarted(store: store, settings: settings)

        XCTAssertFalse(cleared)
        XCTAssertEqual(store.items.count, 1)
    }

    /// Boot time is recorded even while the behaviour is off, so switching it on
    /// does not immediately treat the running session as a new one.
    func testReenablingAfterARestartDoesNotClearTheCurrentSession() {
        var disabled = ClickitSettings.default
        disabled.clearHistoryOnRestart = false

        let store = makeStore()
        makeService(bootTime: firstBoot).resetIfSystemRestarted(store: store, settings: disabled)
        makeService(bootTime: secondBoot).resetIfSystemRestarted(store: store, settings: disabled)
        store.insert(makeTextItem("copied after re-enabling"))

        let cleared = makeService(bootTime: secondBoot)
            .resetIfSystemRestarted(store: store, settings: .default)

        XCTAssertFalse(cleared)
        XCTAssertEqual(store.items.count, 1)
    }

    /// The reported boot time drifts slightly when the clock is adjusted; that
    /// must not read as a reboot.
    func testSubSecondBootTimeDriftIsNotARestart() {
        let store = makeStore()
        makeService(bootTime: firstBoot).resetIfSystemRestarted(store: store, settings: .default)
        store.insert(makeTextItem("still here"))

        let drifted = firstBoot.addingTimeInterval(2)
        let cleared = makeService(bootTime: drifted)
            .resetIfSystemRestarted(store: store, settings: .default)

        XCTAssertFalse(cleared)
        XCTAssertEqual(store.items.count, 1)
    }

    func testUnreadableBootTimeLeavesHistoryAlone() {
        let store = makeStore()
        makeService(bootTime: firstBoot).resetIfSystemRestarted(store: store, settings: .default)
        store.insert(makeTextItem("untouched"))

        let cleared = makeService(bootTime: nil)
            .resetIfSystemRestarted(store: store, settings: .default)

        XCTAssertFalse(cleared)
        XCTAssertEqual(store.items.count, 1)
    }

    func testHistorySurvivesRestartInTheDatabaseUntilTheResetRuns() throws {
        let store = try makeSQLiteStore()
        makeService(bootTime: firstBoot).resetIfSystemRestarted(store: store, settings: .default)
        store.insert(makeTextItem("written before the restart"))
        store.insert(makeTextItem("pinned", pinned: true))

        // Simulate relaunching after a reboot: reopen the database, then reset.
        let reopened = try makeSQLiteStore()
        XCTAssertEqual(reopened.items.count, 2, "the database should still hold both items")

        makeService(bootTime: secondBoot).resetIfSystemRestarted(store: reopened, settings: .default)

        XCTAssertEqual(reopened.items.map(\.textContent), ["pinned"])
        XCTAssertEqual(try makeSQLiteStore().items.map(\.textContent), ["pinned"], "the clear must reach disk")
    }

    /// The real provider must return something plausible on this machine.
    func testSystemBootTimeIsReadable() throws {
        let bootTime = try XCTUnwrap(SystemBootTimeProvider().bootTime)

        XCTAssertLessThan(bootTime, Date())
        XCTAssertGreaterThan(bootTime, Date(timeIntervalSince1970: 1_000_000_000))
    }
}
