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

    /// The widest and *tallest the panel is ever allowed to get*, not the size it
    /// is drawn at. The window is sized from this once, so resizing never fights
    /// the SwiftUI animation, and the expanded content is laid out inside it.
    ///
    /// The height the panel actually uses is measured from its content — see
    /// `NotchViewModel.contentSize`. This is only the ceiling that measurement is
    /// clamped to, so it should be comfortably larger than the tallest tab rather
    /// than tuned to it: a ceiling that fits exactly is a ceiling that clips the
    /// moment a widget grows a row, on a Mac with a taller notch, or at a larger
    /// text size. Extra headroom here costs nothing — the window is transparent
    /// and the panel simply never grows into it.
    static let expandedContentSize = CGSize(width: 560, height: 320)

    /// Extra room around the content for the drop shadow and the hover margin.
    static let windowInset = CGSize(width: 90, height: 60)

    private var peekHeight: CGFloat { max(notchSize.height + 8, 40) }

    /// While media is playing: artwork on one side of the notch, the equaliser on
    /// the other, and nothing else. Only as wide as those two need, so the strips
    /// sit close to the notch rather than stranded at the far edges.
    var mediaPeekSize: CGSize {
        CGSize(width: max(notchSize.width + 120, 240), height: peekHeight)
    }

    /// While a banner is up: wide enough to carry a readable line or two of text,
    /// because a transient notification is nothing without its message.
    var bannerPeekSize: CGSize {
        CGSize(width: max(notchSize.width + 260, 360), height: peekHeight)
    }

    /// - Parameter hasBanner: whether the peek is currently carrying a banner,
    ///   which is the only thing in it that needs room for text.
    func contentSize(for state: NotchState, hasBanner: Bool = false) -> CGSize {
        switch state {
        case .collapsed: return notchSize
        case .peek: return hasBanner ? bannerPeekSize : mediaPeekSize
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
    func hitRect(for state: NotchState, hasBanner: Bool = false) -> CGRect {
        hitRect(ofSize: contentSize(for: state, hasBanner: hasBanner))
    }

    /// Same rect in screen coordinates, for the global pointer test.
    func screenRect(for state: NotchState, hasBanner: Bool = false) -> CGRect {
        screenRect(ofSize: contentSize(for: state, hasBanner: hasBanner))
    }

    /// The zone the pointer has to be in to keep a given state alive. Padded
    /// outward so arriving from below the menu bar registers, and so small
    /// pointer jitter at the edge does not flicker the panel shut.
    func hoverRect(for state: NotchState, hasBanner: Bool = false) -> CGRect {
        hoverRect(
            ofSize: contentSize(for: state, hasBanner: hasBanner),
            isExpanded: state.isExpanded
        )
    }

    // MARK: Measured sizes

    /// The expanded panel is only as tall as its content, which is not something
    /// geometry can know — it depends on which widget is showing and what is in
    /// it. These take the size directly so the panel can be hit-tested against
    /// what is actually on screen rather than against its maximum.

    func hitRect(ofSize content: CGSize) -> CGRect {
        let window = windowSize
        return CGRect(
            x: (window.width - content.width) / 2,
            y: window.height - content.height,
            width: content.width,
            height: content.height
        )
    }

    func screenRect(ofSize content: CGSize) -> CGRect {
        hitRect(ofSize: content).offsetBy(dx: windowFrame.origin.x, dy: windowFrame.origin.y)
    }

    /// Where a file being dragged has to reach for the panel to open itself.
    ///
    /// Deliberately far more generous than the hover zone. The collapsed panel is
    /// the notch and nothing else — on a Mac that means the camera housing, where
    /// the pointer is *invisible*, so asking someone to release a file onto it is
    /// asking them to aim at something they cannot see. Opening as the drag gets
    /// close turns an invisible 179pt strip into the whole expanded panel.
    ///
    /// It can afford to be this large because it only applies while a drag is
    /// actually in flight; nothing here affects ordinary clicks.
    func dropCatchRect() -> CGRect {
        dropCatchHitRect().offsetBy(dx: windowFrame.origin.x, dy: windowFrame.origin.y)
    }

    /// The same zone in window coordinates, for hit testing.
    func dropCatchHitRect() -> CGRect {
        let rect = hitRect(for: .collapsed)
        let padX: CGFloat = 150
        let padY: CGFloat = 60
        return CGRect(
            x: rect.minX - padX,
            y: rect.minY - padY,
            width: rect.width + padX * 2,
            height: rect.height + padY
        )
    }

    func hoverRect(ofSize content: CGSize, isExpanded: Bool) -> CGRect {
        let rect = screenRect(ofSize: content)
        let padX: CGFloat = isExpanded ? 12 : 18
        let padY: CGFloat = isExpanded ? 12 : 4
        return CGRect(
            x: rect.minX - padX,
            y: rect.minY - padY,
            width: rect.width + padX * 2,
            height: rect.height + padY
        )
    }
}
