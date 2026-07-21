import AppKit
import Carbon.HIToolbox
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

    /// Command-Shift-V: the same fingers as paste with one extra key, which is
    /// as close to a convention as "paste, but let me choose which one" has.
    ///
    /// Command-V itself is deliberately never taken. Binding it would stop
    /// pasting from working anywhere on the machine, including inside Clickit's
    /// own search field, and would leave the user unable to paste at all if
    /// Clickit ever stopped responding.
    static let `default` = KeyboardShortcutConfiguration(
        keyCode: 0x09,
        modifierFlagsRawValue: NSEvent.ModifierFlags([.command, .shift]).rawValue
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

    /// Carbon uses its own modifier bits, unrelated to `NSEvent.ModifierFlags`.
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifierFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { carbon |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    /// A shortcut with no modifiers would swallow an ordinary keystroke
    /// system-wide, so it is never accepted.
    var isValid: Bool {
        !modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }

    private static func keyName(for keyCode: UInt16) -> String {
        // Layout-aware translation via UCKeyTranslate is a later refinement;
        // this covers the keys a recorder is realistically given.
        let names: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
            0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
            0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x1F: "O",
            0x20: "U", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x28: "K",
            0x2D: "N", 0x2E: "M",
            0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6",
            0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0",
            0x31: "Space", 0x24: "Return", 0x30: "Tab", 0x35: "Escape",
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

enum GlobalShortcutError: LocalizedError {
    case invalidShortcut
    case registrationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidShortcut:
            "A global shortcut needs at least one modifier key."
        case .registrationFailed(let status):
            status == OSStatus(eventHotKeyExistsErr)
                ? "That shortcut is already claimed by another application. Pick a different one."
                : "The shortcut could not be registered (error \(status))."
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

/// Registers a system-wide hotkey through Carbon's `RegisterEventHotKey`.
///
/// Carbon is deprecated, but this remains the only public API for a global
/// hotkey that does **not** require Accessibility permission. The alternative,
/// `CGEvent.tapCreate`, would mean asking the user to let Clickit observe every
/// keystroke on the machine — an unreasonable trade for opening a window.
@MainActor
final class ShortcutService: GlobalShortcutRegistering {
    var isSupported: Bool { true }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (@MainActor () -> Void)?

    /// Four-character signature identifying Clickit's hotkeys to Carbon.
    private static let signature: OSType = 0x434C_4B54  // "CLKT"

    // No `deinit` cleanup: the Carbon refs are main-actor state and a
    // nonisolated deinit cannot touch them. Owners call `unregister()` —
    // `AppEnvironment.stop()` does, from `applicationWillTerminate`.

    func register(_ configuration: KeyboardShortcutConfiguration, handler: @escaping @MainActor () -> Void) throws {
        guard configuration.isValid else { throw GlobalShortcutError.invalidShortcut }

        unregister()
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }

                var pressedID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressedID
                )
                guard status == noErr, pressedID.signature == ShortcutService.signature else {
                    return OSStatus(eventNotHandledErr)
                }

                let service = Unmanaged<ShortcutService>.fromOpaque(context).takeUnretainedValue()
                // The Carbon callback arrives on the main thread, but it is not
                // statically known to be, so the hop is explicit.
                MainActor.assumeIsolated { service.handler?() }
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(configuration.keyCode),
            configuration.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            unregister()
            throw GlobalShortcutError.registrationFailed(status: status)
        }
        ClickitLog.shortcut.info(
            "Registered global shortcut \(configuration.displayString, privacy: .public)"
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        handler = nil
    }
}
