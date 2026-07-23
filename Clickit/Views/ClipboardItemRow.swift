import SwiftUI

/// One entry in the history list.
///
/// Pure presentation: every action is a closure supplied by the list, so the
/// row never touches a service.
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let environment: AppEnvironment
    let isSelected: Bool
    /// Position in the list, when it is one of the first nine and therefore
    /// reachable with a Command-number shortcut.
    let shortcutNumber: Int?
    let queuePosition: Int?
    let onActivate: () -> Void
    let onToggleQueue: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    var showsActionsForSelection = true

    @State private var isHovering = false
    @Environment(\.controlActiveState) private var controlActiveState

    private var isWindowActive: Bool { controlActiveState != .inactive }

    /// White on the accent fill, otherwise the standard label colours. Applied
    /// to the whole row so the thumbnail glyph and action icons follow the title
    /// instead of each deciding for themselves.
    private var isHighlighted: Bool { isSelected && isWindowActive }

    var body: some View {
        HStack(spacing: 10) {
            ClipboardPreviewView(item: item, environment: environment, isHighlighted: isHighlighted)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailingAccessory
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .rowHighlight(isSelected: isSelected, isHovering: isHovering, isWindowActive: isWindowActive)
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.type.displayName): \(title)")
        .accessibilityValue(
            queuePosition.map { "\(subtitle), paste queue position \($0)" } ?? subtitle
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The thumbnail already says what kind of item this is, so the title does
    /// not repeat it. Images have no text to show, so they are named by type.
    private var title: String {
        item.type == .image ? "Image" : item.previewText
    }

    private var subtitle: String {
        var parts = [RelativeTimeFormatter.string(for: item.lastUsedAt)]
        if item.type == .image {
            parts.append(FileSizeFormatter.string(fromByteCount: item.byteSize))
        }
        if let source = item.sourceApplication, !source.isEmpty {
            parts.append(source)
        }
        return parts.joined(separator: " · ")
    }

    /// Hovering swaps the shortcut hint for the actions it stands in for, which
    /// keeps the row quiet at rest without hiding what it can do.
    @ViewBuilder
    private var trailingAccessory: some View {
        if isHovering || (isSelected && showsActionsForSelection) {
            HStack(spacing: 2) {
                actionButton(
                    systemName: queuePosition == nil ? "plus.square" : "minus.square",
                    help: queuePosition == nil
                        ? "Add to paste queue and start Live Queue"
                        : "Remove from paste queue",
                    action: onToggleQueue
                )
                actionButton(
                    systemName: item.isPinned ? "pin.fill" : "pin",
                    help: item.isPinned ? "Unpin" : "Pin",
                    action: onTogglePin
                )
                actionButton(systemName: "trash", help: "Delete", action: onDelete)
            }
        } else if let queuePosition {
            Text("\(queuePosition)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 17, minHeight: 17)
                .background(Circle().fill(Color.accentColor.opacity(0.16)))
                .foregroundStyle(.tint)
                .accessibilityLabel("Paste queue position \(queuePosition)")
        } else if item.isPinned {
            // Pinned state has to stay readable when the row is at rest.
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } else if let shortcutNumber {
            Text("⌘\(shortcutNumber)")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private func actionButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
        .help(help)
    }
}
