import SwiftUI

/// Explains why picking an item is not pasting, and offers the fix.
///
/// Automatic pasting fails quietly when the permission is missing: the item
/// still reaches the clipboard, so from the user's side Clickit simply appears
/// not to work. This is the only place that difference is visible.
struct AccessibilityNoticeView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(primaryTitle, action: primaryAction)
                        .controlSize(.small)
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

    private var title: String {
        switch environment.accessibilityStatus {
        case .revoked: "Pasting stopped working"
        case .notGranted, .satisfied: "Clickit can paste for you"
        }
    }

    private var message: String {
        switch environment.accessibilityStatus {
        case .revoked:
            // Naming the cause matters: the entry still looks enabled in System
            // Settings, so the obvious fix of toggling it does nothing.
            "This usually follows an update. Remove Clickit from Accessibility in System Settings, add it again, then reopen Clickit."
        case .notGranted, .satisfied:
            "Grant Accessibility access and picked items paste straight into whatever you were typing in."
        }
    }

    /// A revoked grant cannot be re-requested: macOS shows its prompt only once
    /// per application, so the only route left is System Settings.
    private var primaryTitle: String {
        environment.accessibilityStatus == .revoked ? "Open System Settings" : "Grant Access"
    }

    private func primaryAction() {
        if environment.accessibilityStatus == .revoked {
            AccessibilityService.openSettingsPane()
        } else {
            environment.requestAccessibilityAccess()
        }
    }
}
