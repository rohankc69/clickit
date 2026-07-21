import SwiftUI

/// Explains why picking an item is not pasting, and offers the fix.
///
/// Automatic pasting fails quietly when the permission is missing: the item
/// still reaches the clipboard, so from the user's side Clickit simply appears
/// not to work. This is the only place that difference is visible.
struct AccessibilityNoticeView: View {
    @Bindable var environment: AppEnvironment

    /// Set once the repair is done. The grant cannot take effect until Clickit
    /// starts again, because the trust answer is cached for the process.
    @State private var needsRelaunch = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 5) {
                Text(needsRelaunch ? "Almost done" : title)
                    .font(.system(size: 12, weight: .medium))
                Text(needsRelaunch ? Self.relaunchMessage : message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if needsRelaunch {
                        Button("Reopen Clickit") { AccessibilityService.relaunch() }
                            .controlSize(.small)
                    } else {
                        Button(primaryTitle, action: primaryAction)
                            .controlSize(.small)
                    }
                    Button("Not Now") {
                        environment.isAccessibilityNoticeDismissed = true
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
    }

    private static let relaunchMessage =
        "Approve Clickit in System Settings if asked, then reopen it so the change takes effect."

    private var title: String {
        switch environment.accessibilityStatus {
        case .revoked: "Pasting stopped working after an update"
        case .notGranted, .satisfied: "Clickit can paste for you"
        }
    }

    private var message: String {
        switch environment.accessibilityStatus {
        case .revoked:
            "The update left a permission macOS can no longer match. Repairing it takes a moment."
        case .notGranted, .satisfied:
            "Grant Accessibility access to paste picked items automatically."
        }
    }

    private var primaryTitle: String {
        environment.accessibilityStatus == .revoked ? "Repair" : "Grant Access"
    }

    /// Repair does the whole sequence: discard the unmatched record, ask again,
    /// and offer the relaunch that makes the answer take effect. Left to the
    /// user, it means finding the right pane, knowing that the toggle is a
    /// decoy, and removing an entry that looks correct.
    private func primaryAction() {
        guard environment.accessibilityStatus == .revoked else {
            environment.requestAccessibilityAccess()
            return
        }
        if environment.repairAccessibilityAccess() {
            needsRelaunch = true
        } else {
            AccessibilityService.openSettingsPane()
        }
    }
}
