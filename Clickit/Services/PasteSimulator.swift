import AppKit
import CoreGraphics

enum ClickitEventMarker {
    static let syntheticPaste: Int64 = 0x434C_4B54_5053_5445 // "CLKTPSTE"
}

/// Presses Command-V into whatever application the user came from.
@MainActor
protocol PasteSimulating: AnyObject {
    /// Returns `false` when the keystroke could not be posted, so the caller can
    /// tell the user the item is on the clipboard and needs a manual paste.
    @discardableResult
    func pasteIntoFrontmostApplication() -> Bool
}

/// Synthesises the paste keystroke.
///
/// This is the only part of Clickit that acts on another application rather
/// than observing, and it is why the auto-paste feature needs Accessibility
/// permission. Without that permission `CGEvent.post` silently does nothing —
/// it does not fail loudly — so the trust check happens before posting rather
/// than after.
@MainActor
final class PasteSimulator: PasteSimulating {
    private let accessibility: AccessibilityAuthorizing
    private static let virtualKeyV: CGKeyCode = 0x09

    init(accessibility: AccessibilityAuthorizing) {
        self.accessibility = accessibility
    }

    @discardableResult
    func pasteIntoFrontmostApplication() -> Bool {
        guard accessibility.isTrusted else {
            ClickitLog.shortcut.notice("Skipping auto-paste: Accessibility access not granted")
            return false
        }

        // `.privateState` keeps Clickit's synthetic keystroke from inheriting
        // modifier keys the user happens to be holding, which would otherwise
        // turn Command-V into Command-Shift-V and paste as plain text.
        guard let source = CGEventSource(stateID: .privateState) else {
            ClickitLog.shortcut.error("Could not create an event source for auto-paste")
            return false
        }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.virtualKeyV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.virtualKeyV, keyDown: false)
        else {
            ClickitLog.shortcut.error("Could not construct the paste keystroke")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.setIntegerValueField(.eventSourceUserData, value: ClickitEventMarker.syntheticPaste)
        keyUp.setIntegerValueField(.eventSourceUserData, value: ClickitEventMarker.syntheticPaste)
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
