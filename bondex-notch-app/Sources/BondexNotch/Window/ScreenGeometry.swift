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
    /// Raised from 320 when the agent card arrived: Home can now carry three
    /// agent rows *and* a media row *and* the gauges, which is about 360pt, and a
    /// ceiling below that clipped the gauges off the bottom rather than failing
    /// visibly. Headroom here is free — the window is transparent and the panel
    /// only ever grows into what it measures.
    /// The user can make the panel narrower or wider. The window reserves the
    /// largest supported footprint once, while `NotchViewModel.contentSize`
    /// chooses the live width without ever resizing the AppKit window.
    static let expandedContentSize = CGSize(width: 680, height: 520)

    /// Extra room around the content for the drop shadow and the hover margin.
    static let windowInset = CGSize(width: 90, height: 60)

    /// The peek is exactly as tall as the hardware notch, so it reads as the
    /// notch widening rather than as a second shape hanging below it.
    ///
    /// Without a hardware notch the stand-in pill can be as short as a hidden
    /// menu bar's 24pt, which cannot hold two lines — a banner's title and
    /// subtitle, or two agents' clocks stacked — so it gets a 32pt floor there.
    /// There is no hardware edge on those displays for the extra height to
    /// misalign with.
    static let minimumPeekHeight: CGFloat = 32

    var peekHeight: CGFloat {
        hasHardwareNotch ? notchSize.height : max(notchSize.height, Self.minimumPeekHeight)
    }

    /// While media is playing: artwork on one side of the notch, the equaliser on
    /// the other, and nothing else. Only as wide as those two need, so the strips
    /// sit close to the notch rather than stranded at the far edges.
    var mediaPeekSize: CGSize {
        CGSize(width: max(notchSize.width + 120, 240), height: peekHeight)
    }

    // Every peek is a strip either side of the notch, and `PeekView` gives each
    // side exactly half of what is left over — the middle is the camera
    // housing, where nothing can be seen. So these widths are "notch + two
    // wings", and each wing has to hold what that peek puts in it. They used
    // to be sized as if the content could spill towards the middle, which it
    // did: the volume rail and the start of a long banner line were drawn
    // under the hardware notch, invisible on every Mac that has one.

    /// While a banner is up: wide enough to carry a readable line or two of text,
    /// because a transient notification is nothing without its message. Wings
    /// of 150pt hold a 136pt line beside its padding — enough for
    /// "Download complete · 7.4 GB" without losing the size.
    var bannerPeekSize: CGSize {
        CGSize(width: max(notchSize.width + 300, 440), height: peekHeight)
    }

    /// Wings of 130pt: a title and a subtitle of up to 116pt.
    var livePeekSize: CGSize {
        CGSize(width: max(notchSize.width + 260, 400), height: peekHeight)
    }

    /// Hardware controls need room for an icon, a readable meter and a value,
    /// but should still feel lighter than a notification banner. Wings of 120pt
    /// fit the 60pt rail, its value and the padding.
    var systemHUDPeekSize: CGSize {
        CGSize(width: max(notchSize.width + 240, 380), height: peekHeight)
    }

    /// Privacy activity needs only one or two device marks and a short label,
    /// and shares the hardware feedback's footprint so the two swap cleanly.
    var privacyPeekSize: CGSize { systemHUDPeekSize }

    var focusPeekSize: CGSize {
        CGSize(width: max(notchSize.width + 165, 310), height: peekHeight)
    }

    /// Same wings as live progress: a title line and "In 7 min".
    var meetingPeekSize: CGSize {
        CGSize(width: max(notchSize.width + 260, 400), height: peekHeight)
    }

    /// The width either side of the notch that a peek of `width` can draw in.
    func peekWingWidth(forPeekWidth width: CGFloat) -> CGFloat {
        max((width - notchSize.width) / 2, 0)
    }

    /// While agents are working: a mark for each one on the left, and their
    /// clocks on the right.
    ///
    /// Sized from the count rather than fixed at the worst case. One agent needs
    /// about as much room as playback does; three would be stranded at the far
    /// edges of a strip wide enough for three if it never shrank back. The width
    /// changing as a second agent starts is not a glitch — it is the panel
    /// growing to hold something that genuinely arrived, and the spring animates
    /// it like any other state change.
    ///
    /// Each extra agent adds 25pt a side: one more 21pt mark and its gap on the
    /// left, which is also more than half a column of small clocks needs on the
    /// right, since those stack two to a column.
    static let agentPeekGrowth: CGFloat = 50

    func agentPeekSize(agents: Int) -> CGSize {
        let extra = CGFloat(max(agents - 1, 0)) * Self.agentPeekGrowth
        return CGSize(width: max(notchSize.width + 120 + extra, 240), height: peekHeight)
    }

    /// - Parameter peek: what the peek is carrying, which is the only thing that
    ///   changes its width.
    func contentSize(for state: NotchState, peek: PeekContent = .media) -> CGSize {
        switch state {
        case .collapsed: return notchSize
        case .peek:
            switch peek {
            case .systemHUD: return systemHUDPeekSize
            case .privacy: return privacyPeekSize
            case .focus: return focusPeekSize
            case .meeting: return meetingPeekSize
            case .media: return mediaPeekSize
            case .live: return livePeekSize
            case .agent(let agents): return agentPeekSize(agents: agents)
            case .banner: return bannerPeekSize
            }
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
    func hitRect(for state: NotchState, peek: PeekContent = .media) -> CGRect {
        hitRect(ofSize: contentSize(for: state, peek: peek))
    }

    /// Same rect in screen coordinates, for the global pointer test.
    func screenRect(for state: NotchState, peek: PeekContent = .media) -> CGRect {
        screenRect(ofSize: contentSize(for: state, peek: peek))
    }

    /// The zone the pointer has to be in to keep a given state alive. Padded
    /// outward so arriving from below the menu bar registers, and so small
    /// pointer jitter at the edge does not flicker the panel shut.
    func hoverRect(for state: NotchState, peek: PeekContent = .media) -> CGRect {
        hoverRect(
            ofSize: contentSize(for: state, peek: peek),
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

    /// Whether a pointer location (`NSEvent.mouseLocation`, or a click in a
    /// non-flipped view) falls inside a rect.
    ///
    /// Not `CGRect.contains`, which treats the top edge as outside. Mouse
    /// locations run from just above 0 up to *and including* the screen's
    /// `maxY` — measured: a cursor pushed against the top of a 982pt-tall
    /// display reports y = 982.0. Every rect here hangs from the top of the
    /// screen, so `contains` rejected exactly the row the pointer lands on when
    /// it is thrown at the notch, and the panel only opened if the pointer
    /// stopped a pixel short. `NSMouseInRect` is AppKit's own rule for this:
    /// top edge in, bottom edge out.
    static func pointer(_ location: CGPoint, isIn rect: CGRect) -> Bool {
        NSMouseInRect(location, rect, false)
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
