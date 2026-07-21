import SwiftUI

struct SettingsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        TabView {
            GeneralSettingsView(environment: environment)
                .tabItem { Label("General", systemImage: "gearshape") }
            RetentionSettingsView(environment: environment)
                .tabItem { Label("Retention", systemImage: "clock.arrow.circlepath") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            PrivacySettingsView(environment: environment)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 460, height: 380)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        Form {
            Section {
                Toggle("Pause clipboard monitoring", isOn: pausedBinding)
                Toggle("Confirm captures in the menu bar", isOn: flashBinding)
                LabeledContent("Poll interval") {
                    Picker("", selection: pollIntervalBinding) {
                        Text("0.25s").tag(0.25)
                        Text("0.5s").tag(0.5)
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
            } footer: {
                Text("macOS does not notify apps when the clipboard changes, so Clickit checks a counter on this interval. When a capture is confirmed, the menu-bar icon briefly shows a checkmark.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Global shortcut") {
                LabeledContent("Open Clickit") {
                    Text(KeyboardShortcutConfiguration.default.displayString)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                UnavailableNote("Not implemented yet — the shortcut is proposed, not active. Use the menu-bar icon for now. (Roadmap phase 4)")
            }

            Section("Launch") {
                UnavailableNote("Launch at login is not implemented yet. (Roadmap phase 4)")
            }
        }
        .formStyle(.grouped)
    }

    private var pausedBinding: Binding<Bool> {
        Binding(
            get: { environment.isMonitoringPaused },
            set: { newValue in
                guard newValue != environment.isMonitoringPaused else { return }
                environment.toggleMonitoring()
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

private struct RetentionSettingsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        Form {
            Section {
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
            } header: {
                Text("Limits")
            }

            Section {
                Toggle("Clear history when the Mac restarts", isOn: clearOnRestartBinding)
            } footer: {
                Text("Keeps history to the current session at this Mac. Pinned items are always kept. Quitting and relaunching Clickit does not clear anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Expiry") {
                Stepper(
                    "Text and links: \(settings.textRetentionDays) days",
                    value: binding(\.textRetentionDays),
                    in: 1...365
                )
                Stepper(
                    "Images and screenshots: \(settings.imageRetentionDays) days",
                    value: binding(\.imageRetentionDays),
                    in: 1...365
                )
            }

            Section {
                LabeledContent("Current usage") {
                    Text(FileSizeFormatter.string(fromByteCount: environment.clipboardStore.totalByteSize))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Run Cleanup Now") { environment.runCleanup() }
                    Spacer()
                    Button("Clear All History", role: .destructive) {
                        environment.clearHistory(includingPinned: true)
                    }
                }
            } footer: {
                Text("Pinned items never expire and are never removed automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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

private struct PrivacySettingsView: View {
    @Bindable var environment: AppEnvironment
    @State private var newBundleIdentifier = ""

    var body: some View {
        Form {
            Section {
                Text("Clickit stores everything on this Mac. It makes no network requests, has no accounts, and collects no telemetry.")
                    .font(.callout)
            }

            Section("Excluded applications") {
                ForEach(environment.settingsStore.settings.excludedBundleIdentifiers, id: \.self) { identifier in
                    HStack {
                        Text(identifier).monospaced()
                        Spacer()
                        Button("Remove") { remove(identifier) }
                            .buttonStyle(.link)
                    }
                }
                HStack {
                    TextField("Bundle identifier, e.g. com.agilebits.onepassword7", text: $newBundleIdentifier)
                        .textFieldStyle(.roundedBorder)
                    Button("Add", action: add)
                        .disabled(newBundleIdentifier.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                UnavailableNote("Partly implemented: exclusions are matched against the frontmost app at the time of the copy, which is a best-effort guess rather than the true source. There is no app picker yet. (Roadmap phase 4)")
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let trimmed = newBundleIdentifier.trimmingCharacters(in: .whitespaces)
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

/// Reference list of what the popover responds to.
///
/// Read-only for now: these are fixed bindings inside Clickit's own window, not
/// system-wide hotkeys. Making them user-assignable belongs with the global
/// shortcut work in roadmap phase 4.
private struct ShortcutsSettingsView: View {
    private struct Entry: Identifiable {
        let id = UUID()
        let keys: String
        let action: String
    }

    private let navigation: [Entry] = [
        Entry(keys: "Up / Down", action: "Move through history"),
        Entry(keys: "Return", action: "Restore the selected item and close"),
        Entry(keys: "Command-1 to 9", action: "Restore by position"),
        Entry(keys: "Escape", action: "Clear the search, or close"),
        Entry(keys: "Command-F", action: "Focus the search field"),
    ]

    private let actions: [Entry] = [
        Entry(keys: "Command-P", action: "Pin or unpin the selected item"),
        Entry(keys: "Delete", action: "Delete the selected item"),
        Entry(keys: "Command-Delete", action: "Delete while searching"),
        Entry(keys: "Command-K", action: "Clear history, keeping pinned items"),
        Entry(keys: "Command-M", action: "Pause or resume monitoring"),
        Entry(keys: "Command-Comma", action: "Open Settings"),
        Entry(keys: "Command-Q", action: "Quit Clickit"),
    ]

    var body: some View {
        Form {
            Section("Navigation") {
                ForEach(navigation, content: row)
            }
            Section("Actions") {
                ForEach(actions, content: row)
            }
            Section {
                UnavailableNote("These work while the popover is open. A system-wide shortcut to open Clickit from anywhere is not implemented yet. (Roadmap phase 4)")
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ entry: Entry) -> some View {
        LabeledContent {
            Text(entry.keys)
                .monospaced()
                .foregroundStyle(.secondary)
        } label: {
            Text(entry.action)
        }
    }
}

/// Marks behaviour that is deliberately not wired up yet, so the UI never
/// implies a feature works when it does not.
private struct UnavailableNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "hammer")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
