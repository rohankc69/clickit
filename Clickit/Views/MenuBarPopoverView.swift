import SwiftUI

/// The popover shown from the menu-bar icon: search, history, actions.
///
/// Holds only view state (query, selection). Every mutation goes through
/// `AppEnvironment`.
struct MenuBarPopoverView: View {
    @Bindable var environment: AppEnvironment
    let onClose: () -> Void
    let onOpenSettings: () -> Void
    /// Called after an item has been put on the clipboard. The menu-bar popover
    /// leaves this empty; the caret panel uses it to paste for the user.
    var onActivate: () -> Void = {}

    @State private var searchQuery = ""
    @State private var selectedID: UUID?
    @FocusState private var isSearchFocused: Bool

    /// Pinned entries are hoisted here rather than in the store, which keeps its
    /// order purely recency-based for the retention rules to walk.
    private var visibleItems: [ClipboardItem] {
        let matching = environment.items.filter { $0.matches(searchQuery: searchQuery) }
        return matching.filter(\.isPinned) + matching.filter { !$0.isPinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if environment.shouldShowAccessibilityNotice {
                AccessibilityNoticeView(environment: environment)
                Divider()
            }
            content
            if environment.isLiveQueueActive || !environment.pasteQueue.isEmpty {
                Divider()
                pasteQueueBar
            }
            if let message = environment.lastErrorMessage {
                Divider()
                errorBanner(message)
            }
            Divider()
            footer
        }
        .frame(width: ClickitDesign.surfaceSize.width, height: ClickitDesign.surfaceSize.height)
        .onAppear {
            isSearchFocused = true
            selectedID = visibleItems.first?.id
            // The user may have granted or withdrawn access in System Settings
            // since this was last shown.
            environment.refreshAccessibilityState()
        }
        .onChange(of: searchQuery) { _, _ in
            selectedID = visibleItems.first?.id
        }
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(keys: [.return]) { press in
            press.modifiers.contains(.option) ? toggleQueueSelection() : activateSelection()
        }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(keys: [.delete, .deleteForward]) { press in
            deleteSelection(modifiers: press.modifiers)
        }
        .onKeyPress(keys: Self.commandKeys) { press in
            handleCommandKey(press)
        }
    }

    /// Every action reachable from a footer button also has a key, so the
    /// popover can be driven without the mouse once it is open.
    private static let commandKeys: Set<KeyEquivalent> = [
        "p", "f", "k", "m", ",", "q",
        "1", "2", "3", "4", "5", "6", "7", "8", "9",
    ]

    // MARK: - Sections

    /// Deliberately not a bordered text field: the search sits at the top of the
    /// surface with nothing above it, so a full-width bar reads more like the
    /// system's own search UI than a control floating in a header would.
    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            TextField("Search history", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
                // The field consumes Return for submission before an ancestor
                // sees it, so queueing needs to be handled at the focused view.
                .onKeyPress(keys: [.return]) { press in
                    guard press.modifiers.contains(.option) else { return .ignored }
                    return toggleQueueSelection()
                }
                .onSubmit { _ = activateSelection() }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    @ViewBuilder
    private var content: some View {
        if visibleItems.isEmpty {
            EmptyClipboardView(reason: emptyReason)
        } else {
            ClipboardListView(
                items: visibleItems,
                environment: environment,
                selectedID: $selectedID,
                onActivate: restore,
                onToggleQueue: environment.togglePasteQueue,
                onTogglePin: environment.togglePin,
                onDelete: delete
            )
        }
    }

    private var emptyReason: EmptyClipboardView.Reason {
        if !searchQuery.isEmpty {
            .noSearchResults(query: searchQuery)
        } else if environment.isMonitoringPaused {
            .monitoringPaused
        } else {
            .noHistory
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Dismiss") { environment.lastErrorMessage = nil }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private var pasteQueueBar: some View {
        HStack(spacing: 7) {
            liveQueueStatus

            Spacer(minLength: 6)

            Text(KeyboardShortcutConfiguration.toggleLiveQueue.displayString)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            if !environment.pasteQueue.isEmpty {
                Button {
                    environment.clearPasteQueue()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear paste queue")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var liveQueueStatus: some View {
        if environment.isLiveQueueActive {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Live Queue On - \(environment.pasteQueue.count) queued")
                    .font(.system(size: 11, weight: .semibold))
                Text(environment.pasteQueue.isEmpty
                    ? "Copy normally to build the queue"
                    : "Press Command-V to paste the next item")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: "rectangle.stack.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(environment.pasteQueue.count) queued")
                    .font(.system(size: 11, weight: .semibold))
                if let next = environment.nextQueuedItem {
                    Text("Next: \(next.previewText)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            footerButton(
                systemName: environment.isMonitoringPaused ? "play.fill" : "pause.fill",
                help: environment.isMonitoringPaused ? "Resume monitoring" : "Pause monitoring",
                action: environment.toggleMonitoring
            )
            footerButton(systemName: "trash", help: "Clear history (keeps pinned items)") {
                environment.clearHistory()
                selectedID = nil
            }

            Spacer(minLength: 8)

            Text(itemCountLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            footerButton(systemName: "gearshape", help: "Settings", action: onOpenSettings)
            footerButton(systemName: "power", help: "Quit Clickit") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
    }

    private var itemCountLabel: String {
        let count = environment.items.count
        return "\(count) item\(count == 1 ? "" : "s")"
    }

    /// Borderless at rest with a hover fill, matching the toolbar buttons macOS
    /// uses in its own compact windows.
    private func footerButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        FooterButton(systemName: systemName, help: help, action: action)
    }

    // MARK: - Intents

    private func restore(_ item: ClipboardItem) {
        environment.restore(item)
        onClose()
        onActivate()
    }

    private func delete(_ item: ClipboardItem) {
        let items = visibleItems
        if selectedID == item.id {
            let index = items.firstIndex(of: item)
            let next = index.map { items.index(after: $0) }.flatMap { items.indices.contains($0) ? items[$0] : nil }
            selectedID = next?.id ?? items.first(where: { $0.id != item.id })?.id
        }
        environment.delete(item)
    }

    // MARK: - Keyboard

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let items = visibleItems
        guard !items.isEmpty else { return .ignored }

        guard let current = selectedID, let index = items.firstIndex(where: { $0.id == current }) else {
            selectedID = items.first?.id
            return .handled
        }
        let target = min(max(index + offset, 0), items.count - 1)
        selectedID = items[target].id
        return .handled
    }

    private func activateSelection() -> KeyPress.Result {
        guard let selectedID, let item = visibleItems.first(where: { $0.id == selectedID }) else {
            return .ignored
        }
        restore(item)
        return .handled
    }

    private func toggleQueueSelection() -> KeyPress.Result {
        guard let selectedItem else { return .ignored }
        environment.togglePasteQueue(selectedItem)
        return .handled
    }

    private func handleEscape() -> KeyPress.Result {
        if searchQuery.isEmpty {
            onClose()
        } else {
            searchQuery = ""
        }
        return .handled
    }

    /// Command-modified keys for the footer actions, plus Command-1 through
    /// Command-9 to restore by position.
    ///
    /// Everything here requires Command, so ordinary typing in the search field
    /// is never intercepted.
    private func handleCommandKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.command) else { return .ignored }

        if let digit = press.characters.first, let position = Int(String(digit)), position >= 1 {
            let items = visibleItems
            guard position <= items.count else { return .ignored }
            restore(items[position - 1])
            return .handled
        }

        switch press.characters {
        case "f":
            isSearchFocused = true
        case "p":
            guard let item = selectedItem else { return .ignored }
            environment.togglePin(item)
        case "k":
            environment.clearHistory()
            selectedID = nil
        case "m":
            environment.toggleMonitoring()
        case ",":
            onOpenSettings()
        case "q":
            NSApp.terminate(nil)
        default:
            return .ignored
        }
        return .handled
    }

    private var selectedItem: ClipboardItem? {
        guard let selectedID else { return nil }
        return visibleItems.first { $0.id == selectedID }
    }

    /// A bare Delete is left to the search field while the user is typing,
    /// otherwise backspacing a query would silently destroy history entries.
    private func deleteSelection(modifiers: EventModifiers) -> KeyPress.Result {
        guard modifiers.contains(.command) || searchQuery.isEmpty else { return .ignored }
        guard let selectedID, let item = visibleItems.first(where: { $0.id == selectedID }) else {
            return .ignored
        }
        delete(item)
        return .handled
    }
}

/// A footer action. Split out because the hover fill needs its own state, and a
/// `@State` property cannot live inside a view-builder method.
private struct FooterButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .frame(width: 26, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovering ? Color.primary.opacity(0.09) : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { isHovering = $0 }
        .help(help)
    }
}
