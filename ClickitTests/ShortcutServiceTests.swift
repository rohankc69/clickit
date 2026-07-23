import XCTest
@testable import Clickit

@MainActor
final class ShortcutServiceTests: XCTestCase {
    func testPressRunsImmediatelyAndIgnoresRepeatsUntilRelease() {
        let coordinator = ShortcutGestureCoordinator()
        var pressCount = 0

        coordinator.press(.openClickit) { pressCount += 1 }
        coordinator.press(.openClickit) { pressCount += 1 }
        XCTAssertEqual(pressCount, 1)

        coordinator.release(.openClickit)
        coordinator.press(.openClickit) { pressCount += 1 }
        XCTAssertEqual(pressCount, 2)
    }

    func testCancelAllAllowsFreshShortcutPresses() {
        let coordinator = ShortcutGestureCoordinator()
        var pressCount = 0

        coordinator.press(.openClickit) { pressCount += 1 }
        coordinator.cancelAll()
        coordinator.press(.openClickit) { pressCount += 1 }

        XCTAssertEqual(pressCount, 2)
    }
}
