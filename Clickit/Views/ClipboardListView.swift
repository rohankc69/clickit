import SwiftUI

/// Scrollable history list.
///
/// A `LazyVStack` rather than a `List`: a plain list swallows single clicks for
/// its own selection handling, and this popover needs one click to mean
/// "restore this item and close".
struct ClipboardListView: View {
    let items: [ClipboardItem]
    let environment: AppEnvironment
    @Binding var selectedID: UUID?
    let onActivate: (ClipboardItem) -> Void
    let onTogglePin: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(items) { item in
                        ClipboardItemRow(
                            item: item,
                            environment: environment,
                            isSelected: item.id == selectedID,
                            onActivate: { onActivate(item) },
                            onTogglePin: { onTogglePin(item) },
                            onDelete: { onDelete(item) }
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.none) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}
