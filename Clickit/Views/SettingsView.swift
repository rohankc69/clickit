import SwiftUI

/// The panes of the Settings window, in toolbar order.
///
/// Each pane declares its own height so the window can resize to fit, the way
/// System Settings and most Apple applications do, rather than padding every
/// pane out to the tallest one.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case history
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .history: "History"
        case .privacy: "Privacy"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .history: "clock"
        case .privacy: "hand.raised"
        }
    }

    var contentSize: CGSize {
        switch self {
        case .general: CGSize(width: 520, height: 400)
        case .shortcuts: CGSize(width: 520, height: 440)
        case .history: CGSize(width: 520, height: 460)
        case .privacy: CGSize(width: 520, height: 420)
        }
    }

    @MainActor @ViewBuilder
    func view(environment: AppEnvironment) -> some View {
        switch self {
        case .general: GeneralSettingsView(environment: environment)
        case .shortcuts: ShortcutsSettingsView(environment: environment)
        case .history: HistorySettingsView(environment: environment)
        case .privacy: PrivacySettingsView(environment: environment)
        }
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        Form {
            Section {
                Toggle("Record items I copy", isOn: recordingBinding)
                Toggle("Confirm each capture in the menu bar", isOn: flashBinding)
                Picker("Check for changes", selection: pollIntervalBinding) {
                    Text("Every 0.25 seconds").tag(0.25)
                    Text("Every 0.5 seconds").tag(0.5)
                    Text("Every second").tag(1.0)
                    Text("Every 2 seconds").tag(2.0)
                }
            } footer: {
                Caption("macOS does not notify applications when the clipboard changes, so Clickit checks on this interval.")
            }

            Section {
                Toggle("Paste automatically when I pick an item", isOn: autoPasteBinding)
                switch environment.accessibilityStatus {
                case .satisfied:
                    EmptyView()
                case .notGranted:
                    PermissionRow(message: "Accessibility access is required") {
                        environment.requestAccessibilityAccess()
                    }
                case .revoked:
                    // The stale entry still reads as enabled, so telling the
                    // user to remove it is the whole point of this message.
                    PermissionRow(
                        message: "Access was reset, most likely by an update",
                        detail: "Remove Clickit under Accessibility, add it again, then reopen Clickit.",
                        buttonTitle: "Open System Settings"
                    ) {
                        AccessibilityService.openSettingsPane()
                    }
                }
            } header: {
                Text("Pasting")
            } footer: {
                Caption("Used to find your text cursor and to press Command-V for you. Without it, items are placed on the clipboard and you paste them yourself.")
            }

            Section("Startup") {
                Toggle("Open Clickit at login", isOn: .constant(false))
                    .disabled(true)
                Caption("Not available yet.")
            }
        }
        .formStyle(.grouped)
    }

    /// Presented as recording rather than pausing, so the switch reads on for
    /// the state the user wants.
    private var recordingBinding: Binding<Bool> {
        Binding(
            get: { !environment.isMonitoringPaused },
            set: { newValue in
                guard newValue == environment.isMonitoringPaused else { return }
                environment.toggleMonitoring()
            }
        )
    }

    private var autoPasteBinding: Binding<Bool> {
        Binding(
            get: { environment.settingsStore.settings.autoPasteEnabled },
            set: { newValue in
                environment.settingsStore.settings.autoPasteEnabled = newValue
                // Asking at the moment the user opts in is the only point at
                // which the system prompt explains itself.
                if newValue, !environment.isAccessibilityTrusted {
                    environment.requestAccessibilityAccess()
                }
            }
        )
    }

    private var flashBinding: Binding<Bool> {
        Binding(
            get: { environment.settingsStore.settings.flashOnCapture },
            set: { environment.settingsStore.settings.flashOnCapture = $0 }
        )
    }

    private var pollIntervalBinding: Binding<Double> {
        Binding(
            get: { environment.settingsStore.settings.pollInterval },
            set: { newValue in
                environment.settingsStore.settings.pollInterval = newValue
                environment.settingsChanged()
            }
        )
    }
}

// MARK: - Shortcuts

private struct ShortcutsSettingsView: View {
    @Bindable var environment: AppEnvironment

    private struct Entry: Identifiable {
        let id = UUID()
        let keys: String
        let action: String
    }

    private let navigation: [Entry] = [
        Entry(keys: "Up, Down", action: "Move through history"),
        Entry(keys: "Return", action: "Paste the selected item"),
        Entry(keys: "Command-1 to 9", action: "Paste by position"),
        Entry(keys: "Command-F", action: "Search"),
        Entry(keys: "Escape", action: "Clear the search, or close"),
    ]

    private let actions: [Entry] = [
        Entry(keys: "Command-P", action: "Pin or unpin"),
        Entry(keys: "Delete", action: "Delete the selected item"),
        Entry(keys: "Command-K", action: "Clear history, keeping pinned items"),
        Entry(keys: "Command-M", action: "Pause or resume recording"),
        Entry(keys: "Command-Comma", action: "Settings"),
        Entry(keys: "Command-Q", action: "Quit"),
    ]

    var body: some View {
        Form {
            Section {
                LabeledContent("Open at the text cursor") {
                    KeyCombination(environment.settingsStore.settings.openShortcut.displayString)
                }
                if let shortcutError = environment.shortcutError {
                    Label(shortcutError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Caption("Cannot be changed yet.")
            } header: {
                Text("Anywhere")
            } footer: {
                Caption("Command-V is never taken and keeps working as it always has.")
            }

            Section("In Clickit") {
                ForEach(navigation, content: row)
            }

            Section {
                ForEach(actions, content: row)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ entry: Entry) -> some View {
        LabeledContent(entry.action) {
            KeyCombination(entry.keys)
        }
    }
}

// MARK: - History

private struct HistorySettingsView: View {
    @Bindable var environment: AppEnvironment
    @State private var isConfirmingClearAll = false

    var body: some View {
        Form {
            Section("Limits") {
                Stepper(
                    "Keep at most \(settings.maxItems) items",
                    value: binding(\.maxItems),
                    in: 50...10_000,
                    step: 50
                )
                Stepper(
                    "Use at most \(settings.maxStorageBytes / FileSizeFormatter.megabyte) MB",
                    value: megabytesBinding,
                    in: 50...5_000,
                    step: 50
                )
            }

            Section {
                Stepper(
                    "Text and links after \(settings.textRetentionDays) days",
                    value: binding(\.textRetentionDays),
                    in: 1...365
                )
                Stepper(
                    "Images after \(settings.imageRetentionDays) days",
                    value: binding(\.imageRetentionDays),
                    in: 1...365
                )
            } header: {
                Text("Expiry")
            } footer: {
                Caption("Pinned items never expire.")
            }

            Section {
                Toggle("Clear history when this Mac restarts", isOn: clearOnRestartBinding)
            } footer: {
                Caption("Quitting and reopening Clickit clears nothing. Pinned items are always kept.")
            }

            Section("Storage") {
                LabeledContent("Currently using") {
                    Text(FileSizeFormatter.string(fromByteCount: environment.clipboardStore.totalByteSize))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Clean Up Now") { environment.runCleanup() }
                    Spacer()
                    Button("Clear All History") { isConfirmingClearAll = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Clear all history, including pinned items?",
            isPresented: $isConfirmingClearAll,
            titleVisibility: .visible
        ) {
            Button("Clear All History", role: .destructive) {
                environment.clearHistory(includingPinned: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var settings: ClickitSettings {
        environment.settingsStore.settings
    }

    private func binding(_ keyPath: WritableKeyPath<ClickitSettings, Int>) -> Binding<Int> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                environment.settingsStore.settings[keyPath: keyPath] = newValue
                environment.settingsChanged()
            }
        )
    }

    private var clearOnRestartBinding: Binding<Bool> {
        Binding(
            get: { settings.clearHistoryOnRestart },
            set: { environment.settingsStore.settings.clearHistoryOnRestart = $0 }
        )
    }

    private var megabytesBinding: Binding<Int> {
        Binding(
            get: { settings.maxStorageBytes / FileSizeFormatter.megabyte },
            set: { newValue in
                environment.settingsStore.settings.maxStorageBytes = FileSizeFormatter.megabytes(newValue)
                environment.settingsChanged()
            }
        )
    }
}

// MARK: - Privacy

private struct PrivacySettingsView: View {
    @Bindable var environment: AppEnvironment
    @State private var newBundleIdentifier = ""

    var body: some View {
        Form {
            Section {
                Label {
                    Text("Everything stays on this Mac. Clickit makes no network requests, has no accounts, and collects no telemetry.")
                } icon: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.green)
                }
            }

            Section {
                if environment.settingsStore.settings.excludedBundleIdentifiers.isEmpty {
                    Text("No applications excluded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(environment.settingsStore.settings.excludedBundleIdentifiers, id: \.self) { identifier in
                        HStack {
                            Text(identifier)
                                .monospaced()
                            Spacer()
                            Button("Remove") { remove(identifier) }
                                .buttonStyle(.link)
                        }
                    }
                }
                HStack {
                    TextField("Bundle identifier", text: $newBundleIdentifier, prompt: Text("com.example.app"))
                        .textFieldStyle(.roundedBorder)
                    Button("Add", action: add)
                        .disabled(trimmedIdentifier.isEmpty)
                }
            } header: {
                Text("Excluded applications")
            } footer: {
                Caption("Copies are attributed to whichever application is frontmost at the time, which is a guess rather than the true source. Do not rely on this as a security boundary.")
            }
        }
        .formStyle(.grouped)
    }

    private var trimmedIdentifier: String {
        newBundleIdentifier.trimmingCharacters(in: .whitespaces)
    }

    private func add() {
        let trimmed = trimmedIdentifier
        guard !trimmed.isEmpty,
              !environment.settingsStore.settings.excludedBundleIdentifiers.contains(trimmed)
        else { return }
        environment.settingsStore.settings.excludedBundleIdentifiers.append(trimmed)
        newBundleIdentifier = ""
    }

    private func remove(_ identifier: String) {
        environment.settingsStore.settings.excludedBundleIdentifiers.removeAll { $0 == identifier }
    }
}

// MARK: - Shared pieces

/// Explanatory text under a section. Kept to one short sentence: a settings
/// pane that argues with the user reads as unfinished.
private struct Caption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

/// A key combination, styled the way system UI presents one.
private struct KeyCombination: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

/// Shown when a feature is switched on but the permission behind it is missing.
private struct PermissionRow: View {
    let message: String
    var detail: String?
    var buttonTitle = "Grant Access"
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Button(buttonTitle, action: action)
        }
    }
}
