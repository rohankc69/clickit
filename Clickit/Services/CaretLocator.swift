import AppKit
import ApplicationServices

struct QuickPasteAnchor: Equatable {
    enum Source: Equatable {
        case caret
        case focusedElement
        case focusedWindow
        case pointer
    }

    let rect: CGRect
    let source: Source
}

/// Finds where on screen to put the picker.
@MainActor
protocol CaretLocating: AnyObject {
    /// Best available anchor, in AppKit screen coordinates (bottom-left origin).
    func anchor() -> QuickPasteAnchor
}

/// Locates the text insertion point of whatever application is frontmost.
///
/// The answer degrades rather than fails. In order of preference:
///
/// 1. The caret rectangle reported by the focused text element. Exactly what the
///    user asked for, and what native text views report accurately.
/// 2. The focused control. Web views and cross-platform editors often expose
///    their bounds even when they do not expose exact caret geometry.
/// 3. The focused window, so the picker at least stays on the display receiving
///    keyboard input.
/// 4. The mouse pointer, when Accessibility is unavailable entirely.
///
/// Falling all the way back is not a bug. It is what happens without permission,
/// and the picker still opens somewhere sensible.
@MainActor
final class CaretLocator: CaretLocating {
    private let accessibility: AccessibilityAuthorizing

    init(accessibility: AccessibilityAuthorizing) {
        self.accessibility = accessibility
    }

    func anchor() -> QuickPasteAnchor {
        guard accessibility.isTrusted, let focused = focusedElement() else {
            return QuickPasteAnchor(rect: mouseRect(), source: .pointer)
        }
        if let rect = caretRect(for: focused) {
            return QuickPasteAnchor(rect: rect, source: .caret)
        }
        if let rect = elementRect(focused) {
            return QuickPasteAnchor(rect: rect, source: .focusedElement)
        }
        if let rect = focusedWindowRect(for: focused) {
            return QuickPasteAnchor(rect: rect, source: .focusedWindow)
        }
        return QuickPasteAnchor(rect: mouseRect(), source: .pointer)
    }

    // MARK: - Accessibility queries

    private func caretRect(for focused: AXUIElement) -> CGRect? {
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

        guard CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        // The type-ID check above makes this Core Foundation cast safe.
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect),
              CaretGeometry.isValid(rect, allowsZeroSize: false)
        else { return nil }
        return convertFromQuartz(rect)
    }

    private func elementRect(_ element: AXUIElement) -> CGRect? {
        rect(positionAndSizeOf: element)
    }

    private func focusedWindowRect(for focused: AXUIElement) -> CGRect? {
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXWindowAttribute as CFString, &windowValue
        ) == .success,
              let windowValue,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        else { return nil }

        // The type-ID check above makes this Core Foundation cast safe.
        // swiftlint:disable:next force_cast
        return rect(positionAndSizeOf: windowValue as! AXUIElement)
    }

    private func rect(positionAndSizeOf element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        // The type-ID checks above make these Core Foundation casts safe.
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              // swiftlint:disable:next force_cast
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              CaretGeometry.isValid(CGRect(origin: origin, size: size), allowsZeroSize: false)
        else { return nil }

        return convertFromQuartz(CGRect(origin: origin, size: size))
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &element
        ) == .success,
              let element,
              CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }

        // The type-ID check above makes this Core Foundation cast safe.
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
        return CaretGeometry.appKitRect(fromAccessibility: rect, primaryScreenFrame: primary.frame)
    }
}

enum CaretGeometry {
    static func isValid(_ rect: CGRect, allowsZeroSize: Bool) -> Bool {
        let components = [rect.origin.x, rect.origin.y, rect.width, rect.height]
        guard components.allSatisfy(\.isFinite), rect.width >= 0, rect.height >= 0 else {
            return false
        }
        return allowsZeroSize || rect.width > 0 || rect.height > 0
    }

    static func appKitRect(fromAccessibility rect: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenFrame.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
