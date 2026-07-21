import SwiftUI

/// The popover shown from the menu-bar icon: search, history, actions.
///
/// Holds only view state (query, selection). Every mutation goes through
/// `AppEnvironment`.
struct MenuBarPopoverView: View {
    @Bindable var environment: AppEnvironment
    let onClose: () -> Void
    let onOpenSettings: () -> Void

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
            content
            if let message = environment.lastErrorMessage {
                errorBanner(message)
            }
            Divider()
            footer
        }
        .frame(width: 360, height: 420)
        .onAppear {
            isSearchFocused = true
            selectedID = visibleItems.first?.id
        }
        .onChange(of: searchQuery) { _, _ in
            selectedID = visibleItems.first?.id
        }
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.return) { activateSelection() }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(keys: [.delete, .deleteForward]) { press in
            deleteSelection(modifiers: press.modifiers)
        }
    }

    // MARK: - Sections

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Search clipboard history", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)
                .onSubmit { _ = activateSelection() }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Dismiss") { environment.lastErrorMessage = nil }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.12))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            footerButton(
                systemName: environment.isMonitoringPaused ? "play.circle" : "pause.circle",
                help: environment.isMonitoringPaused ? "Resume monitoring" : "Pause monitoring",
                action: environment.toggleMonitoring
            )
            footerButton(systemName: "trash", help: "Clear history (keeps pinned items)") {
                environment.clearHistory()
                selectedID = nil
            }

            Spacer()

            Text("\(environment.items.count) item\(environment.items.count == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            footerButton(systemName: "gearshape", help: "Settings", action: onOpenSettings)
            footerButton(systemName: "power", help: "Quit Clickit") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func footerButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    // MARK: - Intents

    private func restore(_ item: ClipboardItem) {
        environment.restore(item)
        onClose()
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

    private func handleEscape() -> KeyPress.Result {
        if searchQuery.isEmpty {
            onClose()
        } else {
            searchQuery = ""
        }
        return .handled
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
