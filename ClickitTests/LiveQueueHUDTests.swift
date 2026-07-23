import XCTest
@testable import Clickit

final class LiveQueueHUDTests: XCTestCase {
    func testVisibilityCoversRecordingAndRemainingQueueItems() {
        XCTAssertFalse(LiveQueueHUDLayout.shouldShow(isLiveQueueActive: false, queueCount: 0))
        XCTAssertTrue(LiveQueueHUDLayout.shouldShow(isLiveQueueActive: true, queueCount: 0))
        XCTAssertTrue(LiveQueueHUDLayout.shouldShow(isLiveQueueActive: false, queueCount: 1))
    }

    func testHeightCapsVisibleRowsAtFiveAndAddsOverflowStack() {
        let fiveItemsHeight = LiveQueueHUDLayout.headerHeight
            + CGFloat(LiveQueueHUDLayout.maxVisibleItems) * LiveQueueHUDLayout.rowHeight

        XCTAssertEqual(LiveQueueHUDLayout.height(queueCount: 0), 96)
        XCTAssertEqual(LiveQueueHUDLayout.height(queueCount: 5), fiveItemsHeight)
        XCTAssertEqual(
            LiveQueueHUDLayout.height(queueCount: 6),
            fiveItemsHeight + LiveQueueHUDLayout.overflowHeight
        )
        XCTAssertEqual(
            LiveQueueHUDLayout.height(queueCount: 100),
            fiveItemsHeight + LiveQueueHUDLayout.overflowHeight
        )
    }

    func testFrameAnchorsToTopRightOfVisibleMainScreen() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1_400, height: 900)

        let frame = LiveQueueHUDLayout.frame(in: visibleFrame, queueCount: 2)

        XCTAssertEqual(frame.maxX, visibleFrame.maxX - LiveQueueHUDLayout.screenInset)
        XCTAssertEqual(frame.maxY, visibleFrame.maxY - LiveQueueHUDLayout.screenInset)
        XCTAssertEqual(frame.width, LiveQueueHUDLayout.width)
        XCTAssertEqual(frame.height, LiveQueueHUDLayout.height(queueCount: 2))
    }
}
