import AppKit
import ApplicationServices

/// Finds where on screen to put the picker.
@MainActor
protocol CaretLocating: AnyObject {
    /// Best available anchor, in AppKit screen coordinates (bottom-left origin).
    func anchorRect() -> CGRect
}

/// Locates the text insertion point of whatever application is frontmost.
///
/// The answer degrades rather than fails. In order of preference:
///
/// 1. The caret rectangle reported by the focused text element. Exactly what the
///    user asked for, and what native text views report accurately.
/// 2. The bottom-left of the focused window. Web views and some editors expose
///    no caret geometry at all, and a picker near the right window still beats
///    one on the other side of the display.
/// 3. The mouse pointer, when Accessibility is unavailable entirely.
///
/// Falling all the way back is not a bug. It is what happens without permission,
/// and the picker still opens somewhere sensible.
@MainActor
final class CaretLocator: CaretLocating {
    private let accessibility: AccessibilityAuthorizing

    init(accessibility: AccessibilityAuthorizing) {
        self.accessibility = accessibility
    }

    func anchorRect() -> CGRect {
        guard accessibility.isTrusted else { return mouseRect() }
        return caretRect() ?? focusedWindowRect() ?? mouseRect()
    }

    // MARK: - Accessibility queries

    private func caretRect() -> CGRect? {
        guard let focused = focusedElement() else { return nil }

        // The caret is a zero-length selection; its bounds are only available
        // through the parameterised bounds-for-range attribute.
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        ) == .success, let rangeValue else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success, let boundsValue else { return nil }

        var rect = CGRect.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        guard rect.width.isFinite, rect.height.isFinite, rect != .zero || rect.origin != .zero else {
            return nil
        }
        return convertFromQuartz(rect)
    }

    private func focusedWindowRect() -> CGRect? {
        guard let focused = focusedElement() else { return nil }

        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXWindowAttribute as CFString, &windowValue
        ) == .success, let windowValue else { return nil }
        // swiftlint:disable:next force_cast
        let window = windowValue as! AXUIElement

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              // swiftlint:disable:next force_cast
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }

        return convertFromQuartz(CGRect(origin: origin, size: size))
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &element
        ) == .success, let element else { return nil }
        // swiftlint:disable:next force_cast
        return (element as! AXUIElement)
    }

    // MARK: - Fallback and coordinates

    private func mouseRect() -> CGRect {
        CGRect(origin: NSEvent.mouseLocation, size: .zero)
    }

    /// Accessibility reports a top-left origin measured from the primary
    /// display; AppKit windows use a bottom-left origin. Without this flip the
    /// picker lands mirrored vertically, which on a tall display puts it off
    /// screen entirely.
    private func convertFromQuartz(_ rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        let flippedY = primary.frame.maxY - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
    }
}
