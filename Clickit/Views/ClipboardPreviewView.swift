import SwiftUI

/// The leading thumbnail in a history row.
///
/// Images get a real thumbnail; everything else gets its type symbol. Image
/// bytes are read lazily through the environment so the list can render before
/// any file I/O happens.
struct ClipboardPreviewView: View {
    let item: ClipboardItem
    let environment: AppEnvironment
    /// Set when the row is drawn on the accent fill, where the usual
    /// translucent tile and secondary glyph would both disappear.
    var isHighlighted = false

    /// Loaded off the render path in `.task`, not computed inline: a computed
    /// property would re-read the file and re-decode on every redraw.
    @State private var thumbnail: NSImage?

    private let side = ClickitDesign.thumbnailSide
    private let shape = RoundedRectangle(
        cornerRadius: ClickitDesign.thumbnailCornerRadius,
        style: .continuous
    )

    var body: some View {
        Group {
            if item.type == .image, let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                symbolTile
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        // A hairline keeps a light screenshot from bleeding into a light row.
        .overlay {
            shape.strokeBorder(
                isHighlighted ? AnyShapeStyle(.white.opacity(0.25)) : AnyShapeStyle(.separator),
                lineWidth: 0.5
            )
        }
        .accessibilityHidden(true)
        // Reloads when the row is reused for a different item; the cache makes a
        // repeat load instant.
        .task(id: item.id) {
            guard item.type == .image else {
                thumbnail = nil
                return
            }
            thumbnail = await environment.thumbnail(for: item, maxPixelSize: ClickitDesign.thumbnailPixelSize)
        }
    }

    private var symbolTile: some View {
        shape
            .fill(isHighlighted ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.quaternary))
            .overlay {
                Image(systemName: item.type.systemImageName)
                    .font(.system(size: 14))
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
    }
}
