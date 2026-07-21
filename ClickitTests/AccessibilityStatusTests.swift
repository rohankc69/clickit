import XCTest
@testable import Clickit

/// Covers telling "never granted" apart from "granted once and lost".
///
/// The distinction exists because an unsigned build changes identity with every
/// update, so macOS stops honouring an existing grant while still listing it as
/// enabled. The two cases need different instructions, and getting them the
/// wrong way round sends the user down a route that cannot work.
@MainActor
final class AccessibilityStatusTests: ClickitTestCase {
    func testStatusIsSatisfiedWhenAutomaticPastingIsOff() {
        var settings = ClickitSettings.default
        settings.autoPasteEnabled = false
        let environment = makeEnvironment(
            settings: settings,
            accessibility: StubAccessibilityService(isTrusted: false)
        )

        XCTAssertEqual(environment.accessibilityStatus, .satisfied)
        XCTAssertFalse(environment.shouldShowAccessibilityNotice)
    }

    func testStatusIsSatisfiedWhenAccessIsGranted() {
        let environment = makeEnvironment(accessibility: StubAccessibilityService(isTrusted: true))

        XCTAssertEqual(environment.accessibilityStatus, .satisfied)
        XCTAssertFalse(environment.shouldShowAccessibilityNotice)
    }

    func testStatusIsNotGrantedBeforeAccessHasEverBeenHeld() {
        let environment = makeEnvironment(accessibility: StubAccessibilityService(isTrusted: false))

        XCTAssertEqual(environment.accessibilityStatus, .notGranted)
        XCTAssertTrue(environment.shouldShowAccessibilityNotice)
    }

    func testHoldingAccessIsRemembered() {
        let accessibility = StubAccessibilityService(isTrusted: true)
        let environment = makeEnvironment(accessibility: accessibility)

        environment.refreshAccessibilityState()

        XCTAssertTrue(environment.settingsStore.settings.hasHadAccessibilityAccess)
    }

    /// The update case: access was held, the bundle changed, and macOS no longer
    /// matches the grant.
    func testLosingHeldAccessReportsRevokedRatherThanNotGranted() {
        let accessibility = StubAccessibilityService(isTrusted: true)
        let environment = makeEnvironment(accessibility: accessibility)
        environment.refreshAccessibilityState()
        XCTAssertEqual(environment.accessibilityStatus, .satisfied)

        accessibility.isTrusted = false

        XCTAssertEqual(environment.accessibilityStatus, .revoked)
        XCTAssertTrue(environment.shouldShowAccessibilityNotice)
    }

    func testRefreshDoesNotClearTheRecordWhenAccessIsLost() {
        let accessibility = StubAccessibilityService(isTrusted: true)
        let environment = makeEnvironment(accessibility: accessibility)
        environment.refreshAccessibilityState()

        accessibility.isTrusted = false
        environment.refreshAccessibilityState()

        // Forgetting here would downgrade the next report to "not granted" and
        // send the user to a prompt that macOS will never show again.
        XCTAssertTrue(environment.settingsStore.settings.hasHadAccessibilityAccess)
        XCTAssertEqual(environment.accessibilityStatus, .revoked)
    }

    func testDismissingHidesTheNoticeWithoutChangingTheStatus() {
        let environment = makeEnvironment(accessibility: StubAccessibilityService(isTrusted: false))

        environment.isAccessibilityNoticeDismissed = true

        XCTAssertFalse(environment.shouldShowAccessibilityNotice)
        XCTAssertEqual(environment.accessibilityStatus, .notGranted)
    }

    /// A failed paste is the moment the user cares most, so it overrides an
    /// earlier dismissal.
    func testAFailedAutomaticPasteBringsTheNoticeBack() {
        let environment = makeEnvironment(accessibility: StubAccessibilityService(isTrusted: false))
        environment.isAccessibilityNoticeDismissed = true

        environment.reportAutoPasteUnavailable()

        XCTAssertTrue(environment.shouldShowAccessibilityNotice)
        XCTAssertNotNil(environment.lastErrorMessage)
    }
}

/// The repair path, which exists because the System Settings checkbox cannot
/// fix a record whose pinned signature no longer matches the binary.
@MainActor
final class AccessibilityRepairTests: ClickitTestCase {
    func testRepairClearsTheRecordAndAsksAgain() {
        let accessibility = StubAccessibilityService(isTrusted: true)
        let environment = makeEnvironment(accessibility: accessibility)
        environment.refreshAccessibilityState()
        accessibility.isTrusted = false
        XCTAssertEqual(environment.accessibilityStatus, .revoked)

        XCTAssertTrue(environment.repairAccessibilityAccess())

        XCTAssertEqual(accessibility.resetCount, 1)
        XCTAssertEqual(accessibility.requestCount, 1)
        // Back to a first-run state, so a second failure is not misreported as
        // another update having broken it.
        XCTAssertFalse(environment.settingsStore.settings.hasHadAccessibilityAccess)
        XCTAssertEqual(environment.accessibilityStatus, .notGranted)
    }

    func testAFailedResetDoesNotPromptOrRewriteState() {
        let accessibility = StubAccessibilityService(isTrusted: true)
        accessibility.resetSucceeds = false
        let environment = makeEnvironment(accessibility: accessibility)
        environment.refreshAccessibilityState()
        accessibility.isTrusted = false

        XCTAssertFalse(environment.repairAccessibilityAccess())

        // Prompting after a failed reset would show nothing, since the stale
        // record is still there. The caller falls back to System Settings.
        XCTAssertEqual(accessibility.requestCount, 0)
        XCTAssertTrue(environment.settingsStore.settings.hasHadAccessibilityAccess)
    }
}
