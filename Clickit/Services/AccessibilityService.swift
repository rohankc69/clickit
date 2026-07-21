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

    /// Discards the existing authorisation record so a fresh one can be made.
    /// Returns whether the reset succeeded.
    func resetAuthorization() -> Bool
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
        ClickitLog.shortcut.notice("Requested Accessibility access")
    }

    /// Removes Clickit's Accessibility records so the grant can be remade.
    ///
    /// Needed because macOS pins an authorisation to the exact code signature
    /// that earned it. An unsigned build is identified by a hash of its own
    /// binary, so every update produces a record that can never match again.
    /// The row stays in System Settings looking enabled, and its checkbox only
    /// flips an allow flag that is never reached, which is why switching it off
    /// and on does nothing at all. Deleting the record is the only way to let a
    /// new one be written.
    ///
    /// `tccutil` is the supported tool for this and only ever acts on the
    /// bundle identifier it is given, so this cannot touch another application's
    /// permissions.
    func resetAuthorization() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleIdentifier]
        // Discarded rather than inherited, so tccutil's chatter stays out of
        // Clickit's own output.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            ClickitLog.shortcut.error("Could not reset Accessibility: \(error.localizedDescription, privacy: .public)")
            return false
        }

        let succeeded = process.terminationStatus == 0
        ClickitLog.shortcut.notice("Reset Accessibility records: \(succeeded ? "ok" : "failed", privacy: .public)")
        return succeeded
    }

    /// Quits and starts again, because the trust answer is cached for the life
    /// of the process: a grant made while Clickit is running is not seen until
    /// it next launches.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
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
