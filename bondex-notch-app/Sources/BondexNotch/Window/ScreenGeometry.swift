import AppKit

/// Measures the hardware notch (or synthesises one) and derives every frame the
/// panel uses.
///
/// All rects returned here are in AppKit *screen* coordinates: origin
/// bottom-left, y increasing upward.
struct NotchGeometry: Equatable {

    /// Size of the physical notch, or the synthetic stand-in on displays
    /// without one.
    let notchSize: CGSize
    /// True when the display actually has a notch, which changes how much the
    /// collapsed state needs to draw (on real notches, nothing).
    let hasHardwareNotch: Bool
    let screenFrame: CGRect

    // MARK: Derivation

    static func measure(screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame

        // `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` are the usable menu
        // bar strips either side of the notch. What is left between them is the
        // notch itself.
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            if width > 1 {
                return NotchGeometry(
                    notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
                    hasHardwareNotch: true,
                    screenFrame: frame
                )
            }
        }

        // No notch: use a pill roughly the size of a notch so the interaction is
        // identical on external and older displays.
        let menuBarHeight = max(frame.height - (screen.visibleFrame.maxY), 24)
        return NotchGeometry(
            notchSize: CGSize(width: 190, height: min(menuBarHeight, 32)),
            hasHardwareNotch: false,
            screenFrame: frame
        )
    }

    // MARK: Content sizes

    /// Widest/tallest the content can ever be. The window is sized from this
    /// once, so resizing never fights the SwiftUI animation.
    static let expandedContentSize = CGSize(width: 560, height: 210)

    /// Extra room around the content for the drop shadow and the hover margin.
    static let windowInset = CGSize(width: 90, height: 60)

    var peekSize: CGSize {
        CGSize(width: max(notchSize.width + 190, 320), height: max(notchSize.height + 6, 38))
    }

    func contentSize(for state: NotchState) -> CGSize {
        switch state {
        case .collapsed: return notchSize
        case .peek: return peekSize
        case .expanded: return Self.expandedContentSize
        }
    }

    /// The window is fixed at the largest footprint; content is laid out inside
    /// it, top-centre aligned.
    var windowSize: CGSize {
        CGSize(
            width: Self.expandedContentSize.width + Self.windowInset.width * 2,
            height: Self.expandedContentSize.height + Self.windowInset.height
        )
    }

    var windowFrame: CGRect {
        let size = windowSize
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Interactive area for a given state, in window coordinates (bottom-left
    /// origin), used for hit testing.
    func hitRect(for state: NotchState) -> CGRect {
        let content = contentSize(for: state)
        let window = windowSize
        return CGRect(
            x: (window.width - content.width) / 2,
            y: window.height - content.height,
            width: content.width,
            height: content.height
        )
    }

    /// Same rect in screen coordinates, for the global pointer test.
    func screenRect(for state: NotchState) -> CGRect {
        let rect = hitRect(for: state)
        let origin = windowFrame.origin
        return rect.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// The zone the pointer has to be in to keep a given state alive. Padded
    /// outward so arriving from below the menu bar registers, and so small
    /// pointer jitter at the edge does not flicker the panel shut.
    func hoverRect(for state: NotchState) -> CGRect {
        let rect = screenRect(for: state)
        let padX: CGFloat = state.isExpanded ? 12 : 18
        let padY: CGFloat = state.isExpanded ? 12 : 4
        return CGRect(
            x: rect.minX - padX,
            y: rect.minY - padY,
            width: rect.width + padX * 2,
            height: rect.height + padY
        )
    }
}
