import XCTest
@testable import Clickit

/// The diagnostics summary is pasted into public issue trackers, so the thing
/// worth testing is not its formatting but what it must never contain.
@MainActor
final class DiagnosticsTests: ClickitTestCase {
    func testSummaryNeverIncludesHistoryContents() {
        let environment = makeEnvironment()
        let secret = "correct-horse-battery-staple"
        environment.clipboardStore.insert(makeTextItem(secret))

        let summary = environment.diagnosticSummary()

        XCTAssertFalse(summary.contains(secret))
        XCTAssertTrue(summary.contains("Items: 1"))
    }

    func testSummaryReportsAccessibilityState() {
        let environment = makeEnvironment(accessibility: StubAccessibilityService(isTrusted: false))

        XCTAssertTrue(environment.diagnosticSummary().contains("Accessibility: not granted"))
    }

    func testSummaryReportsThatAccessWasResetRatherThanNeverGranted() {
        let accessibility = StubAccessibilityService(isTrusted: true)
        let environment = makeEnvironment(accessibility: accessibility)
        environment.refreshAccessibilityState()
        accessibility.isTrusted = false

        XCTAssertTrue(environment.diagnosticSummary().contains("reset"))
    }

    /// Copying diagnostics must not land in the history it is reporting on.
    func testCopyingDiagnosticsIsNotRecordedAsAnItem() {
        let pasteboard = MockPasteboardService()
        let environment = makeEnvironment(pasteboard: pasteboard)
        environment.monitor.start()

        environment.copyDiagnosticsToClipboard()
        environment.monitor.poll()

        XCTAssertEqual(environment.items.count, 0)
    }
}
