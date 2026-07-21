import SwiftUI

/// One entry in the history list.
///
/// Pure presentation: every action is a closure supplied by the list, so the
/// row never touches a service.
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let environment: AppEnvironment
    let isSelected: Bool
    let onActivate: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            ClipboardPreviewView(item: item, environment: environment)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.previewText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 12))

                HStack(spacing: 4) {
                    Text(RelativeTimeFormatter.string(for: item.lastUsedAt))
                    if item.type != .text {
                        Text("·")
                        Text(item.type.displayName)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? .white.opacity(0.8) : Color.secondary)
            }

            Spacer(minLength: 4)

            // Pin stays visible while pinned so the state is readable at rest.
            if isHovering || isSelected || item.isPinned {
                actionButton(
                    systemName: item.isPinned ? "pin.fill" : "pin",
                    help: item.isPinned ? "Unpin" : "Pin",
                    action: onTogglePin
                )
            }
            if isHovering || isSelected {
                actionButton(systemName: "trash", help: "Delete", action: onDelete)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { isHovering = $0 }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.type.displayName): \(item.previewText)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.accentColor : (isHovering ? Color.primary.opacity(0.06) : .clear))
    }

    private func actionButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : .secondary)
        .help(help)
    }
}
