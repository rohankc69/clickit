import AppKit
import SwiftUI

/// Shared measurements and materials for Clickit's two surfaces: the menu-bar
/// popover and the panel shown at the text caret.
///
/// Both render the same view at the same size, so the numbers live here rather
/// than being repeated in the AppKit layer where they would quietly drift apart.
enum ClickitDesign {
    /// Sized for a utility popover: wide enough that a line of text is readable
    /// before it truncates, short enough to stay out of the way.
    static let surfaceSize = CGSize(width: 380, height: 460)

    /// Matches the radius macOS uses for popovers, so the caret panel does not
    /// read as a foreign window next to system UI.
    static let surfaceCornerRadius: CGFloat = 12

    static let rowCornerRadius: CGFloat = 7
    static let listHorizontalInset: CGFloat = 8
    static let thumbnailSide: CGFloat = 32
    static let thumbnailCornerRadius: CGFloat = 6

    /// Pixel budget for a decoded thumbnail: the 32pt tile at up to 3× backing
    /// scale. Decoding to this rather than full size is what keeps image history
    /// off the heap. See `ImageDownsampler`.
    static let thumbnailPixelSize = Int(thumbnailSide) * 3
}

/// Measurements and placement for the read-only queue HUD. The height follows
/// the queue up to five rows; additional entries collapse into one stack row.
enum LiveQueueHUDLayout {
    static let width: CGFloat = 288
    static let screenInset: CGFloat = 18
    static let cornerRadius: CGFloat = 12
    static let headerHeight: CGFloat = 48
    static let rowHeight: CGFloat = 44
    static let emptyHeight: CGFloat = 48
    static let overflowHeight: CGFloat = 32
    static let maxVisibleItems = 5

    static func shouldShow(isLiveQueueActive: Bool, queueCount: Int) -> Bool {
        isLiveQueueActive || queueCount > 0
    }

    static func height(queueCount: Int) -> CGFloat {
        let count = max(queueCount, 0)
        let contentHeight = count == 0
            ? emptyHeight
            : CGFloat(min(count, maxVisibleItems)) * rowHeight
        return headerHeight + contentHeight + (count > maxVisibleItems ? overflowHeight : 0)
    }

    static func frame(in visibleFrame: CGRect, queueCount: Int) -> CGRect {
        let size = CGSize(width: width, height: height(queueCount: queueCount))
        return CGRect(
            x: visibleFrame.maxX - size.width - screenInset,
            y: visibleFrame.maxY - size.height - screenInset,
            width: size.width,
            height: size.height
        )
    }
}

/// Live vibrancy behind the caret panel.
///
/// `NSPopover` supplies its own material, so this is only used by the panel,
/// which is a borderless window with nothing behind it. SwiftUI's `Material`
/// blurs what is inside the window; only `NSVisualEffectView` in
/// `.behindWindow` mode blurs the desktop underneath it.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        // Without this the blur greys out whenever the user's app, rather than
        // Clickit, is the active one -- which is the normal case for the panel.
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

extension View {
    /// Applies a row's selected or hovered background.
    ///
    /// Selection follows the window's active state: a filled accent bar in a
    /// window the user is not looking at reads as though something is still
    /// waiting on them.
    func rowHighlight(isSelected: Bool, isHovering: Bool, isWindowActive: Bool) -> some View {
        background {
            RoundedRectangle(cornerRadius: ClickitDesign.rowCornerRadius, style: .continuous)
                .fill(highlightStyle(isSelected: isSelected, isHovering: isHovering, isWindowActive: isWindowActive))
        }
    }

    private func highlightStyle(isSelected: Bool, isHovering: Bool, isWindowActive: Bool) -> AnyShapeStyle {
        if isSelected, isWindowActive {
            AnyShapeStyle(Color.accentColor)
        } else if isSelected {
            AnyShapeStyle(.quaternary)
        } else if isHovering {
            AnyShapeStyle(Color.primary.opacity(0.07))
        } else {
            AnyShapeStyle(.clear)
        }
    }
}
