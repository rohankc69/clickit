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
