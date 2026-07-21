import AppKit
import ApplicationServices

/// Gatekeeper for the two features that need Accessibility: locating the text
/// caret, and pasting on the user's behalf.
///
/// Kept behind a protocol so the panel and paste paths can be exercised without
/// a trusted process.
@MainActor
protocol AccessibilityAuthorizing: AnyObject {
    /// Whether macOS currently trusts Clickit to inspect and control other apps.
    var isTrusted: Bool { get }

    /// Shows the system prompt, which sends the user to System Settings. macOS
    /// only displays it once per app; afterwards this is a silent no-op and the
    /// user has to enable it manually.
    func requestAccess()
}

@MainActor
final class AccessibilityService: AccessibilityAuthorizing {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccess() {
        guard !isTrusted else { return }
        // The framework exposes this key as a mutable global, which strict
        // concurrency rejects. Its literal value is stable API.
        let promptKey = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        ClickitLog.shortcut.info("Requested Accessibility access")
    }

    /// Opens the exact settings pane, for the case where the one-time prompt has
    /// already been dismissed and the user has no obvious way back.
    static func openSettingsPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
