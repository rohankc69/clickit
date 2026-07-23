import SwiftUI

/// Scrollable history list, grouped into pinned and recent entries.
///
/// A `LazyVStack` rather than a `List`: a plain list swallows single clicks for
/// its own selection handling, and this popover needs one click to mean
/// "restore this item and close".
struct ClipboardListView: View {
    /// Already ordered pinned-first by the caller. Keyboard navigation and the
    /// Command-number shortcuts walk this same order, so the sections below
    /// must not re-sort it.
    let items: [ClipboardItem]
    let environment: AppEnvironment
    @Binding var selectedID: UUID?
    let onActivate: (ClipboardItem) -> Void
    let onToggleQueue: (ClipboardItem) -> Void
    let onTogglePin: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void

    private var pinned: [ClipboardItem] { items.filter(\.isPinned) }
    private var recent: [ClipboardItem] { items.filter { !$0.isPinned } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1, pinnedViews: .sectionHeaders) {
                    // Headers are only worth the vertical space once both groups
                    // exist; with one group the list is self-explanatory.
                    if !pinned.isEmpty, !recent.isEmpty {
                        Section {
                            rows(for: pinned)
                        } header: {
                            sectionHeader("Pinned")
                        }
                        Section {
                            rows(for: recent)
                        } header: {
                            sectionHeader("Recent")
                        }
                    } else {
                        rows(for: items)
                    }
                }
                .padding(.horizontal, ClickitDesign.listHorizontalInset)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.automatic)
            .onChange(of: selectedID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.none) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func rows(for group: [ClipboardItem]) -> some View {
        ForEach(group) { item in
            ClipboardItemRow(
                item: item,
                environment: environment,
                isSelected: item.id == selectedID,
                shortcutNumber: shortcutNumber(for: item),
                queuePosition: environment.pasteQueuePosition(for: item),
                onActivate: { onActivate(item) },
                onToggleQueue: { onToggleQueue(item) },
                onTogglePin: { onTogglePin(item) },
                onDelete: { onDelete(item) }
            )
            .id(item.id)
        }
    }

    /// Command-1 through Command-9 address the first nine entries of the full
    /// list, so the number comes from `items` rather than the section.
    private func shortcutNumber(for item: ClipboardItem) -> Int? {
        guard let index = items.firstIndex(of: item), index < 9 else { return nil }
        return index + 1
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Pinned headers scroll under the rows above them without this.
            .background(.regularMaterial)
    }
}
