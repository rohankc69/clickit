import AppKit
import Foundation

/// A user-replaceable global hotkey.
///
/// Stored as a virtual key code plus modifier flags rather than a character so
/// the binding survives keyboard-layout changes — the same physical key keeps
/// working on AZERTY or Dvorak.
struct KeyboardShortcutConfiguration: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifierFlagsRawValue: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    /// Option-V. Proposed rather than fixed: it is close to Command-V, rarely
    /// claimed by other apps, and deliberately not hard-coded anywhere outside
    /// this value so Settings can replace it.
    static let `default` = KeyboardShortcutConfiguration(
        keyCode: 0x09,
        modifierFlagsRawValue: NSEvent.ModifierFlags.option.rawValue
    )

    var displayString: String {
        var result = ""
        if modifierFlags.contains(.control) { result += "⌃" }
        if modifierFlags.contains(.option) { result += "⌥" }
        if modifierFlags.contains(.shift) { result += "⇧" }
        if modifierFlags.contains(.command) { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    private static func keyName(for keyCode: UInt16) -> String {
        // Minimal ANSI map. A full layout-aware translation via
        // `UCKeyTranslate` arrives with the recorder UI in phase 4.
        switch keyCode {
        case 0x09: "V"
        case 0x08: "C"
        case 0x23: "P"
        case 0x31: "Space"
        default: "Key \(keyCode)"
        }
    }
}

enum GlobalShortcutError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            "Global shortcuts are not implemented yet (roadmap phase 4)."
        }
    }
}

/// Registers a system-wide hotkey that opens the clipboard popover.
@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    var isSupported: Bool { get }
    func register(_ configuration: KeyboardShortcutConfiguration, handler: @escaping @MainActor () -> Void) throws
    func unregister()
}

/// # Not implemented
///
/// Placeholder so the popover-opening path can be wired and injected now, and
/// so Settings has something real to display. It deliberately does **not**
/// register anything: `isSupported` is `false` and `register` throws, because a
/// stub that silently succeeded would be indistinguishable from a broken
/// hotkey.
///
/// The intended implementation is a Carbon `RegisterEventHotKey` handler (still
/// the only public API for a global hotkey that does not require Accessibility
/// permissions). Tracked as roadmap phase 4.
@MainActor
final class ShortcutService: GlobalShortcutRegistering {
    var isSupported: Bool { false }

    func register(_ configuration: KeyboardShortcutConfiguration, handler: @escaping @MainActor () -> Void) throws {
        ClickitLog.shortcut.notice(
            "Global shortcut \(configuration.displayString, privacy: .public) requested but not yet implemented"
        )
        throw GlobalShortcutError.notImplemented
    }

    func unregister() {}
}
