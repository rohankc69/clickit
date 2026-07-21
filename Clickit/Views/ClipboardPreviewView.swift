import SwiftUI

/// The leading thumbnail in a history row.
///
/// Images get a real thumbnail; everything else gets its type symbol. Image
/// bytes are read lazily through the environment so the list can render before
/// any file I/O happens.
struct ClipboardPreviewView: View {
    let item: ClipboardItem
    let environment: AppEnvironment

    private let side: CGFloat = 28

    var body: some View {
        Group {
            if item.type == .image, let image = thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: item.type.systemImageName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: side, height: side)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel(item.type.displayName)
    }

    private var thumbnail: NSImage? {
        guard let data = environment.imageData(for: item) else { return nil }
        return NSImage(data: data)
    }
}
