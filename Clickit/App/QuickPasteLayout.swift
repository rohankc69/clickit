import Foundation

struct QuickPasteDisplay: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

enum QuickPasteSurfaceLayout {
    static let width: CGFloat = 360
    static let searchHeight: CGFloat = 38
    static let footerHeight: CGFloat = 30
    static let rowHeight: CGFloat = 45
    static let listVerticalInset: CGFloat = 12
    static let emptyContentHeight: CGFloat = 96
    static let errorHeight: CGFloat = 48
    static let maxVisibleItems = 5

    static func size(itemCount: Int, hasError: Bool) -> CGSize {
        let listHeight = itemCount > 0
            ? CGFloat(min(itemCount, maxVisibleItems)) * rowHeight + listVerticalInset
            : emptyContentHeight
        let dividers: CGFloat = hasError ? 3 : 2
        let height = searchHeight
            + listHeight
            + footerHeight
            + (hasError ? errorHeight : 0)
            + dividers
        return CGSize(width: width, height: height)
    }
}

enum QuickPasteLayout {
    static let edgeInset: CGFloat = 20

    static func frame(
        anchoredTo anchor: QuickPasteAnchor,
        panelSize: CGSize,
        displays: [QuickPasteDisplay],
        preferredDisplay: QuickPasteDisplay?
    ) -> CGRect {
        guard let display = targetDisplay(
            for: anchor,
            displays: displays,
            preferredDisplay: preferredDisplay
        ) else {
            return CGRect(origin: anchor.rect.origin, size: panelSize)
        }

        let visible = display.visibleFrame
        return CGRect(
            origin: clamped(
                CGPoint(
                    x: visible.maxX - panelSize.width - edgeInset,
                    y: visible.minY + edgeInset
                ),
                panelSize: panelSize,
                visibleFrame: visible,
                inset: edgeInset
            ),
            size: panelSize
        )
    }

    static func targetDisplay(
        for anchor: QuickPasteAnchor,
        displays: [QuickPasteDisplay],
        preferredDisplay: QuickPasteDisplay?
    ) -> QuickPasteDisplay? {
        guard !displays.isEmpty else { return preferredDisplay }

        if anchor.source == .pointer,
           let preferredDisplay,
           displays.contains(preferredDisplay) {
            return preferredDisplay
        }

        let center = anchor.rect.center
        if anchor.source == .caret || anchor.source == .pointer,
           let containing = displays.first(where: { $0.frame.contains(center) }) {
            return containing
        }

        let intersections = displays.map { display in
            (display: display, area: intersectionArea(anchor.rect, display.frame))
        }
        if let largest = intersections.max(by: { lhs, rhs in
            if lhs.area == rhs.area {
                let lhsContains = lhs.display.frame.contains(center)
                let rhsContains = rhs.display.frame.contains(center)
                return !lhsContains && rhsContains
            }
            return lhs.area < rhs.area
        }), largest.area > 0 {
            return largest.display
        }

        return displays.min {
            squaredDistance(from: center, to: $0.frame)
                < squaredDistance(from: center, to: $1.frame)
        }
    }

    private static func clamped(
        _ origin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect,
        inset: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: clamp(
                origin.x,
                lower: visibleFrame.minX + inset,
                upper: visibleFrame.maxX - panelSize.width - inset
            ),
            y: clamp(
                origin.y,
                lower: visibleFrame.minY + inset,
                upper: visibleFrame.maxY - panelSize.height - inset
            )
        )
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return lower }
        return min(max(value, lower), upper)
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
