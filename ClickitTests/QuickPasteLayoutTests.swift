import XCTest
@testable import Clickit

final class QuickPasteLayoutTests: XCTestCase {
    private let panelSize = QuickPasteSurfaceLayout.size(itemCount: 3, hasError: false)

    func testQuickPasteSurfaceUsesContentDrivenHeightCappedAtFiveRows() {
        XCTAssertEqual(QuickPasteSurfaceLayout.size(itemCount: 0, hasError: false).height, 166)
        XCTAssertEqual(QuickPasteSurfaceLayout.size(itemCount: 3, hasError: false).height, 217)
        XCTAssertEqual(
            QuickPasteSurfaceLayout.size(itemCount: 100, hasError: false),
            QuickPasteSurfaceLayout.size(itemCount: 5, hasError: false)
        )
        XCTAssertEqual(
            QuickPasteSurfaceLayout.size(itemCount: 3, hasError: true).height,
            266
        )
    }

    func testCaretChoosesItsDisplayInEveryDirection() {
        let primary = display(x: 0, y: 0, width: 1_440, height: 900)
        let secondaryDisplays = [
            display(x: 1_440, y: 0, width: 1_920, height: 1_080),
            display(x: -1_280, y: 0, width: 1_280, height: 1_024),
            display(x: 0, y: 900, width: 1_440, height: 900),
            display(x: 0, y: -900, width: 1_440, height: 900),
        ]

        for secondary in secondaryDisplays {
            let anchor = QuickPasteAnchor(
                rect: CGRect(x: secondary.frame.midX, y: secondary.frame.midY, width: 2, height: 18),
                source: .caret
            )

            let frame = QuickPasteLayout.frame(
                anchoredTo: anchor,
                panelSize: panelSize,
                displays: [primary, secondary],
                preferredDisplay: primary
            )

            XCTAssertTrue(secondary.visibleFrame.contains(frame), "Failed for \(secondary.frame)")
            XCTAssertEqual(frame.maxX, secondary.visibleFrame.maxX - QuickPasteLayout.edgeInset)
            XCTAssertEqual(frame.minY, secondary.visibleFrame.minY + QuickPasteLayout.edgeInset)
        }
    }

    func testFocusedElementUsesDisplayWithGreatestIntersection() {
        let primary = display(x: 0, y: 0, width: 1_440, height: 900)
        let secondary = display(x: 1_440, y: 0, width: 1_440, height: 900)
        let anchor = QuickPasteAnchor(
            rect: CGRect(x: 1_300, y: 300, width: 500, height: 100),
            source: .focusedElement
        )

        let target = QuickPasteLayout.targetDisplay(
            for: anchor,
            displays: [primary, secondary],
            preferredDisplay: primary
        )

        XCTAssertEqual(target, secondary)
    }

    func testFocusedWindowUsesLowerTrailingPlacementOnItsDominantDisplay() {
        let primary = display(x: 0, y: 0, width: 1_440, height: 900)
        let secondary = display(x: 1_440, y: 0, width: 1_440, height: 900)
        let anchor = QuickPasteAnchor(
            rect: CGRect(x: 1_200, y: 100, width: 1_200, height: 700),
            source: .focusedWindow
        )

        let frame = QuickPasteLayout.frame(
            anchoredTo: anchor,
            panelSize: panelSize,
            displays: [primary, secondary],
            preferredDisplay: primary
        )

        XCTAssertTrue(secondary.visibleFrame.contains(frame))
        XCTAssertEqual(frame.maxX, secondary.visibleFrame.maxX - QuickPasteLayout.edgeInset)
        XCTAssertEqual(frame.minY, secondary.visibleFrame.minY + QuickPasteLayout.edgeInset)
    }

    func testPointerFallbackPrefersDisplayReceivingKeyboardInput() {
        let primary = display(x: 0, y: 0, width: 1_440, height: 900)
        let keyboardDisplay = display(x: 1_440, y: 0, width: 1_440, height: 900)
        let pointerOnPrimary = QuickPasteAnchor(
            rect: CGRect(x: 300, y: 300, width: 0, height: 0),
            source: .pointer
        )

        let frame = QuickPasteLayout.frame(
            anchoredTo: pointerOnPrimary,
            panelSize: panelSize,
            displays: [primary, keyboardDisplay],
            preferredDisplay: keyboardDisplay
        )

        XCTAssertTrue(keyboardDisplay.visibleFrame.contains(frame))
        XCTAssertEqual(frame.maxX, keyboardDisplay.visibleFrame.maxX - QuickPasteLayout.edgeInset)
        XCTAssertEqual(frame.minY, keyboardDisplay.visibleFrame.minY + QuickPasteLayout.edgeInset)
    }

    func testLargeFocusedControlUsesConsistentDisplayEdgePlacement() {
        let screen = display(x: 0, y: 0, width: 1_440, height: 900)
        let largeWebView = QuickPasteAnchor(
            rect: CGRect(x: 280, y: 40, width: 1_100, height: 820),
            source: .focusedElement
        )

        let frame = QuickPasteLayout.frame(
            anchoredTo: largeWebView,
            panelSize: panelSize,
            displays: [screen],
            preferredDisplay: screen
        )

        XCTAssertEqual(frame.maxX, screen.visibleFrame.maxX - QuickPasteLayout.edgeInset)
        XCTAssertEqual(frame.minY, screen.visibleFrame.minY + QuickPasteLayout.edgeInset)
    }

    func testAnchorInDisplayGapChoosesNearestDisplay() {
        let left = display(x: 0, y: 0, width: 1_400, height: 900)
        let right = display(x: 1_500, y: 0, width: 1_400, height: 900)
        let anchor = QuickPasteAnchor(
            rect: CGRect(x: 1_480, y: 400, width: 2, height: 18),
            source: .caret
        )

        let target = QuickPasteLayout.targetDisplay(
            for: anchor,
            displays: [left, right],
            preferredDisplay: left
        )

        XCTAssertEqual(target, right)
    }

    func testFinalFrameIsClampedOnEveryEdge() {
        let screen = display(x: -1_280, y: -300, width: 1_280, height: 1_024)
        let anchors = [
            CGRect(x: screen.frame.minX - 100, y: screen.frame.minY - 100, width: 2, height: 18),
            CGRect(x: screen.frame.maxX + 100, y: screen.frame.maxY + 100, width: 2, height: 18),
        ]

        for rect in anchors {
            let frame = QuickPasteLayout.frame(
                anchoredTo: QuickPasteAnchor(rect: rect, source: .caret),
                panelSize: panelSize,
                displays: [screen],
                preferredDisplay: screen
            )

            XCTAssertTrue(screen.visibleFrame.contains(frame))
        }
    }

    func testAccessibilityCoordinateConversionSupportsDisplaysAboveAndBelowPrimary() {
        let primary = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let aboveInAccessibilityCoordinates = CGRect(x: 500, y: -118, width: 2, height: 18)
        let belowInAccessibilityCoordinates = CGRect(x: 500, y: 1_382, width: 2, height: 18)

        XCTAssertEqual(
            CaretGeometry.appKitRect(
                fromAccessibility: aboveInAccessibilityCoordinates,
                primaryScreenFrame: primary
            ).origin.y,
            1_000
        )
        XCTAssertEqual(
            CaretGeometry.appKitRect(
                fromAccessibility: belowInAccessibilityCoordinates,
                primaryScreenFrame: primary
            ).origin.y,
            -500
        )
    }

    func testInvalidAccessibilityGeometryIsRejected() {
        XCTAssertFalse(CaretGeometry.isValid(
            CGRect(x: CGFloat.nan, y: 0, width: 2, height: 18),
            allowsZeroSize: false
        ))
        XCTAssertFalse(CaretGeometry.isValid(
            CGRect(x: 0, y: CGFloat.infinity, width: 2, height: 18),
            allowsZeroSize: false
        ))
        XCTAssertFalse(CaretGeometry.isValid(
            .null,
            allowsZeroSize: false
        ))
        XCTAssertFalse(CaretGeometry.isValid(.zero, allowsZeroSize: false))
        XCTAssertTrue(CaretGeometry.isValid(
            CGRect(x: 100, y: 100, width: 0, height: 18),
            allowsZeroSize: false
        ))
    }

    private func display(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> QuickPasteDisplay {
        let frame = CGRect(x: x, y: y, width: width, height: height)
        return QuickPasteDisplay(frame: frame, visibleFrame: frame)
    }
}
