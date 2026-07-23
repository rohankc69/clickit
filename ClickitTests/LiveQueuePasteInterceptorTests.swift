import CoreGraphics
import XCTest
@testable import Clickit

@MainActor
final class LiveQueuePasteInterceptorTests: XCTestCase {
    func testMatchesAnUnmodifiedPhysicalCommandV() throws {
        let event = try makeKeyEvent(keyCode: 0x09, flags: .maskCommand)

        XCTAssertTrue(LiveQueuePasteInterceptor.isPhysicalCommandV(type: .keyDown, event: event))
        XCTAssertFalse(LiveQueuePasteInterceptor.isPhysicalCommandV(type: .keyUp, event: event))
    }

    func testRejectsOtherKeysAndModifiedPasteShortcuts() throws {
        XCTAssertFalse(LiveQueuePasteInterceptor.isPhysicalCommandV(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 0x08, flags: .maskCommand)
        ))
        XCTAssertFalse(LiveQueuePasteInterceptor.isPhysicalCommandV(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 0x09, flags: [.maskCommand, .maskShift])
        ))
        XCTAssertFalse(LiveQueuePasteInterceptor.isPhysicalCommandV(
            type: .keyDown,
            event: try makeKeyEvent(keyCode: 0x09, flags: [.maskCommand, .maskAlternate])
        ))
    }

    func testRejectsClickitsSyntheticPasteEvent() throws {
        let event = try makeKeyEvent(keyCode: 0x09, flags: .maskCommand)
        event.setIntegerValueField(.eventSourceUserData, value: ClickitEventMarker.syntheticPaste)

        XCTAssertFalse(LiveQueuePasteInterceptor.isPhysicalCommandV(type: .keyDown, event: event))
    }

    private func makeKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags) throws -> CGEvent {
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true))
        event.flags = flags
        return event
    }
}
