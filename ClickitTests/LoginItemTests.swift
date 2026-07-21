import XCTest
@testable import Clickit

/// Covers launch at login: on by default, applied once, and never fighting a
/// user who turns it off.
@MainActor
final class LoginItemTests: ClickitTestCase {
    func testStartEnablesLaunchAtLoginOnFirstRun() {
        let loginItem = StubLoginItemService(isEnabled: false)
        let environment = makeEnvironment(loginItem: loginItem)

        environment.start()

        XCTAssertEqual(loginItem.setCalls, [true])
        XCTAssertTrue(environment.opensAtLogin)
        XCTAssertTrue(environment.settingsStore.settings.hasConfiguredLoginItem)
    }

    func testStartDoesNotReapplyTheDefaultOnLaterRuns() {
        var settings = ClickitSettings.default
        settings.hasConfiguredLoginItem = true
        // The user has since turned it off.
        let loginItem = StubLoginItemService(isEnabled: false)
        let environment = makeEnvironment(settings: settings, loginItem: loginItem)

        environment.start()

        // Untouched: re-enabling here would override the user's choice.
        XCTAssertTrue(loginItem.setCalls.isEmpty)
        XCTAssertFalse(environment.opensAtLogin)
    }

    func testTurningItOffRetiresTheDefault() {
        let loginItem = StubLoginItemService(isEnabled: true)
        let environment = makeEnvironment(loginItem: loginItem)

        environment.setOpensAtLogin(false)

        XCTAssertFalse(environment.opensAtLogin)
        XCTAssertNil(environment.loginItemError)
        XCTAssertTrue(environment.settingsStore.settings.hasConfiguredLoginItem)

        // A subsequent launch must not switch it back on.
        environment.start()
        XCTAssertFalse(environment.opensAtLogin)
    }

    func testAFailedChangeSurfacesAnErrorAndLeavesStateAsItWas() {
        struct Refused: LocalizedError { var errorDescription: String? { "refused" } }
        let loginItem = StubLoginItemService(isEnabled: false)
        loginItem.failure = Refused()
        let environment = makeEnvironment(loginItem: loginItem)
        // Skip the first-run default so this exercises the user-driven path.
        environment.settingsStore.settings.hasConfiguredLoginItem = true

        environment.setOpensAtLogin(true)

        XCTAssertFalse(environment.opensAtLogin)
        XCTAssertNotNil(environment.loginItemError)
    }

    func testAFailedDefaultDoesNotRetryOnTheNextLaunch() {
        struct Refused: Error {}
        let loginItem = StubLoginItemService(isEnabled: false)
        loginItem.failure = Refused()
        let environment = makeEnvironment(loginItem: loginItem)

        environment.start()
        environment.start()

        // One attempt only: the latch is set even when the attempt fails, so an
        // unsigned build is not retried every launch.
        XCTAssertEqual(loginItem.setCalls, [true])
        XCTAssertTrue(environment.settingsStore.settings.hasConfiguredLoginItem)
    }
}
