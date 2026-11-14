import SwiftUI

/// Persistent queue progress shown on the main display while recording or
/// sequential pasting is in progress. The header and hover controls make the
/// HUD usable as a fallback when Command-V monitoring is unavailable.
struct LiveQueueHUDView: View {
    @Bindable var environment: AppEnvironment
    let onPasteNext: () -> Void

    @State private var hoveredEntryID: UUID?

    private var visibleEntries: [PasteQueueEntry] {
        Array(environment.pasteQueue.prefix(LiveQueueHUDLayout.maxVisibleItems))
    }

    private var overflowCount: Int {
        max(environment.pasteQueue.count - LiveQueueHUDLayout.maxVisibleItems, 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .overlay(alignment: .bottom) { Divider() }
            if visibleEntries.isEmpty {
                emptyState
            } else {
                queueRows
            }
            if overflowCount > 0 {
                overflowRow
                    .overlay(alignment: .top) {
                        Divider().padding(.leading, 46)
                    }
            }
        }
        .frame(
            width: LiveQueueHUDLayout.width,
            height: LiveQueueHUDLayout.height(queueCount: environment.pasteQueue.count)
        )
        .background(VisualEffectBackground(material: .popover))
        .clipShape(surfaceShape)
        .overlay {
            surfaceShape.strokeBorder(.separator, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiveQueueHUDLayout.cornerRadius, style: .continuous)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Live Queue")
                        .font(.system(size: 13, weight: .semibold))
                    Circle()
                        .fill(environment.isLiveQueueActive ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(headerDetail)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HStack(spacing: 2) {
                queueControl(
                    systemName: environment.isLiveQueueActive ? "pause.fill" : "play.fill",
                    help: environment.isLiveQueueActive ? "Pause Live Queue" : "Resume Live Queue"
                ) {
                    environment.toggleLiveQueue()
                }

                if !environment.pasteQueue.isEmpty {
                    queueControl(
                        systemName: "doc.on.clipboard",
                        help: "Paste or copy the next queued item"
                    ) {
                        onPasteNext()
                    }
                    queueControl(
                        systemName: "xmark.circle.fill",
                        help: "Clear paste queue"
                    ) {
                        environment.clearPasteQueue()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: LiveQueueHUDLayout.headerHeight)
    }

    private var headerDetail: String {
        if environment.isLiveQueueActive {
            return environment.pasteQueue.isEmpty
                ? "Waiting for copied items"
                : "\(environment.pasteQueue.count) queued - Command-V pastes next"
        }
        return environment.pasteQueue.isEmpty
            ? "Paused"
            : "Paused - \(environment.pasteQueue.count) queued - Option-Shift-V resumes"
    }

    private func queueControl(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private var queueRows: some View {
        ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
            if let item = environment.item(forQueueEntry: entry) {
                queueRow(entry: entry, item: item, position: index + 1)
                    .overlay(alignment: .bottom) {
                        if index < visibleEntries.count - 1 {
                            Divider().padding(.leading, 54)
                        }
                    }
            }
        }
    }

    private func queueRow(
        entry: PasteQueueEntry,
        item: ClipboardItem,
        position: Int
    ) -> some View {
        let isHovered = hoveredEntryID == entry.id

        return HStack(spacing: 8) {
            Text("\(position)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .trailing)

            ClipboardPreviewView(item: item, environment: environment)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewText)
                    .font(.system(size: 11.5, weight: .regular))
                    .lineLimit(1)
                Text(rowDetail(for: item, position: position))
                    .font(.system(size: 9.5))
                    .foregroundStyle(
                        position == 1 && environment.isLiveQueueActive
                            ? Color.accentColor
                            : Color.secondary
                    )
            }

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                if position > 1 {
                    Button {
                        environment.moveQueuedEntryToFront(id: entry.id)
                    } label: {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .help("Make this the next item")
                }
                Button {
                    environment.removeQueuedEntry(id: entry.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .help("Remove from paste queue")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        .padding(.horizontal, 12)
        .frame(height: LiveQueueHUDLayout.rowHeight)
        .background {
            if position == 1 && environment.isLiveQueueActive {
                Color.accentColor.opacity(0.06)
            }
        }
        .onHover { hovering in
            if hovering {
                hoveredEntryID = entry.id
            } else if hoveredEntryID == entry.id {
                hoveredEntryID = nil
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Queue item \(position), \(item.previewText)")
    }

    private func rowDetail(for item: ClipboardItem, position: Int) -> String {
        position == 1 && environment.isLiveQueueActive ? "Next to paste" : item.type.displayName
    }

    private var emptyState: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text("Copy text or take a screenshot to begin")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: LiveQueueHUDLayout.emptyHeight)
    }

    private var overflowRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            Text("\(overflowCount) more item\(overflowCount == 1 ? "" : "s")")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: LiveQueueHUDLayout.overflowHeight)
        .accessibilityLabel("\(overflowCount) additional queued items")
    }
}
