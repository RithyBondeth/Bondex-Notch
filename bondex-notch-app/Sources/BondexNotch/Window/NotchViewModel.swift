import AppKit
import Combine
import SwiftUI

/// Owns the panel's state machine.
///
/// Inputs: pointer position, whether media is playing, whether a drag is
/// hovering. Output: `state`, which everything else renders from.
@MainActor
final class NotchViewModel: ObservableObject {

    @Published private(set) var state: NotchState = .collapsed
    @Published var tab: NotchTab = .home
    @Published var isDropTargeted = false
    /// Set while a transient banner (track change, download finished) is showing.
    @Published private(set) var banner: NotchEvent?

    @Published private(set) var geometry: NotchGeometry

    /// Latched open by a click, so the panel stays put while the user works in it.
    private var isPinned = false
    private var closeWorkItem: DispatchWorkItem?
    private var openWorkItem: DispatchWorkItem?
    private var bannerWorkItem: DispatchWorkItem?
    private var dragPasteboardChangeCount = -1
    private var dragPasteboardHasFiles = false
    private var cancellables = Set<AnyCancellable>()

    private let settings: SettingsStore
    private let events: EventCenter

    /// Kept in sync by whoever owns the media service, so `peek` can turn on
    /// without this type depending on the service directly.
    var hasLiveActivity = false {
        didSet {
            guard hasLiveActivity != oldValue else { return }
            refreshIdleState()
        }
    }

    init(settings: SettingsStore, events: EventCenter, screen: NSScreen) {
        self.settings = settings
        self.events = events
        self.geometry = NotchGeometry.measure(screen: screen)

        events.$latest
            .compactMap { $0 }
            .sink { [weak self] event in self?.show(banner: event) }
            .store(in: &cancellables)

        settings.$preferences
            .map(\.peekWhilePlaying)
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshIdleState() }
            .store(in: &cancellables)
    }

    // MARK: Geometry

    func updateGeometry(for screen: NSScreen) {
        let measured = NotchGeometry.measure(screen: screen)
        guard measured != geometry else { return }
        geometry = measured
    }

    /// Height the expanded panel needs for what it is currently showing, measured
    /// from the content itself. Nil until the first measurement arrives.
    @Published private(set) var measuredExpandedHeight: CGFloat?

    /// Never let the panel collapse to a sliver if a measurement arrives wrong.
    private let minimumExpandedHeight: CGFloat = 120

    /// What the panel is currently drawing.
    ///
    /// The expanded height is measured rather than fixed, so the panel is exactly
    /// as tall as its content: the Home tab is shorter with nothing playing than
    /// with a media row, and the Music tab does not have to reserve room for the
    /// tallest tab. A single fixed height cannot be right for both — it is either
    /// too short for one (clipping it) or too tall for the other (dead space).
    var contentSize: CGSize {
        guard state.isExpanded else {
            return geometry.contentSize(for: state, hasBanner: banner != nil)
        }
        let maximum = NotchGeometry.expandedContentSize
        let measured = measuredExpandedHeight ?? maximum.height
        return CGSize(
            width: maximum.width,
            height: min(max(measured, minimumExpandedHeight), maximum.height)
        )
    }

    /// The peek is narrower while it is only reporting playback than it is while
    /// carrying a banner, and the expanded panel is only as tall as its content —
    /// so hit testing follows what is drawn, or the panel keeps swallowing clicks
    /// in a margin it is no longer filling.
    var hitRect: CGRect { geometry.hitRect(ofSize: contentSize) }

    /// Reported by the view once SwiftUI has laid the expanded content out.
    func setMeasuredExpandedHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        guard let current = measuredExpandedHeight else {
            // First measurement: adopt it outright. Animating from nothing would
            // fight the spring that is already opening the panel.
            measuredExpandedHeight = height
            return
        }
        guard abs(current - height) > 0.5 else { return }
        withAnimation(Motion.content(settings.motion)) {
            measuredExpandedHeight = height
        }
    }

    // MARK: Pointer

    func pointerMoved(to location: CGPoint) {
        // While expanded, the whole panel keeps it open; while closed, only the
        // notch strip does.
        let liveRect = geometry.hoverRect(ofSize: contentSize, isExpanded: state.isExpanded)
        let triggerRect = geometry.hoverRect(for: .collapsed)

        // A file on its way to the shelf opens the panel early and from much
        // further out, so there is something visible to aim at. Pointer events
        // keep arriving throughout a drag, which is what makes this possible.
        if !state.isExpanded,
           geometry.dropCatchRect().contains(location),
           isFileDragInFlight {
            openForDrop()
            return
        }

        if state.isExpanded {
            if liveRect.contains(location) {
                cancelPendingClose()
            } else if !isPinned {
                scheduleClose()
            }
            return
        }

        guard settings.preferences.expandOnHover else {
            cancelPendingOpen()
            return
        }

        if triggerRect.contains(location) || liveRect.contains(location) {
            cancelPendingClose()
            scheduleOpen()
        } else {
            // Left the strip before the dwell elapsed: this was a pointer on its
            // way somewhere else, not a request to open.
            cancelPendingOpen()
        }
    }

    // MARK: Transitions

    func expand() {
        cancelPendingOpen()
        guard state != .expanded else { return }
        cancelPendingClose()
        withAnimation(Motion.panel(settings.motion)) {
            state = .expanded
            banner = nil
        }
    }

    func collapse() {
        isPinned = false
        cancelPendingOpen()
        cancelPendingClose()
        withAnimation(Motion.panel(settings.motion)) {
            state = idleState
        }
    }

    /// Click on the collapsed notch: open and latch.
    func toggle() {
        if state.isExpanded {
            collapse()
        } else {
            isPinned = true
            expand()
        }
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        if !pinned { scheduleClose() }
    }

    func dragEntered() {
        isDropTargeted = true
        guard settings.isUnlocked(.shelf), settings.preferences.shelfEnabled else { return }
        tab = .shelf
        expand()
    }

    // MARK: Drag catching

    /// Whether a file drag is currently in flight anywhere on screen.
    ///
    /// There is no public "is a drag happening" API, but the drag pasteboard
    /// carries the payload while one is, and its change count makes the check
    /// cheap enough to run on pointer moves — reading the items themselves on
    /// every event would not be.
    ///
    /// The pasteboard keeps its contents after a drag finishes, so this can read
    /// true when nothing is being dragged. That is harmless here: the only
    /// consequence is that the notch opens from a little further away, which is
    /// what hovering it does anyway.
    var isFileDragInFlight: Bool {
        let pasteboard = NSPasteboard(name: .drag)
        if pasteboard.changeCount != dragPasteboardChangeCount {
            dragPasteboardChangeCount = pasteboard.changeCount
            dragPasteboardHasFiles = pasteboard.canReadObject(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            )
        }
        // A drag session owns the mouse button, so it reports *no* button pressed —
        // which is exactly what separates a live drag from someone holding the
        // button down over the menu bar after some earlier drag left the
        // pasteboard populated. Without this, an ordinary click near the notch
        // would be swallowed by the enlarged drop zone.
        return dragPasteboardHasFiles && NSEvent.pressedMouseButtons == 0
    }

    /// Opens straight onto the shelf, with no dwell — a drag is already a clear
    /// statement of intent, and waiting would just make the target arrive late.
    private func openForDrop() {
        guard settings.isUnlocked(.shelf), settings.preferences.shelfEnabled else { return }
        cancelPendingClose()
        guard state != .expanded else { return }
        tab = .shelf
        expand()
    }

    func dragExited() {
        isDropTargeted = false
        if !isPinned { scheduleClose() }
    }

    // MARK: Idle presentation

    /// What the panel falls back to when nothing is hovering it: a peek when
    /// something is live, otherwise fully closed.
    private var idleState: NotchState {
        guard hasLiveActivity, settings.preferences.peekWhilePlaying else { return .collapsed }
        return .peek
    }

    private func refreshIdleState() {
        guard !state.isExpanded else { return }
        withAnimation(Motion.panel(settings.motion)) {
            state = idleState
        }
    }

    /// Starts the close countdown, and leaves an already-running one alone.
    ///
    /// Restarting it here would mean the deadline is pushed back by every mouse
    /// move anywhere on screen — so the panel would stay open for as long as the
    /// pointer kept moving, however far away it was. Re-entering the panel is
    /// what cancels the countdown, not moving outside it.
    private func scheduleClose() {
        guard closeWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeWorkItem = nil
            guard !self.isPinned else { return }
            withAnimation(Motion.panel(self.settings.motion)) {
                self.state = self.idleState
            }
        }
        closeWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + settings.preferences.closeDelay,
            execute: work
        )
    }

    private func cancelPendingClose() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
    }

    // MARK: Hover intent

    /// Requires the pointer to dwell on the notch before opening.
    ///
    /// `pointerMoved` fires on every mouse-moved event, so without a dwell the
    /// panel opens on the way past. Re-entering while a dwell is already pending
    /// must not restart it, or a slow drift across the strip never opens at all.
    private func scheduleOpen() {
        guard openWorkItem == nil else { return }

        let delay = settings.preferences.hoverDelay
        guard delay > 0 else {
            expand()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.openWorkItem = nil
            self.expand()
        }
        openWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingOpen() {
        openWorkItem?.cancel()
        openWorkItem = nil
    }

    // MARK: Banners

    private func show(banner event: NotchEvent) {
        // Playback reaches the feed but never the banner; see `deservesBanner`.
        guard event.kind.deservesBanner else { return }

        // Never interrupt the expanded panel with a banner; the feed already
        // shows it there.
        guard !state.isExpanded else { return }

        bannerWorkItem?.cancel()
        // Growing out of the notch is a panel move; swapping one banner for the
        // next inside an existing peek is only a content change.
        let resizes = state == .collapsed
        withAnimation(resizes ? Motion.panel(settings.motion) : Motion.content(settings.motion)) {
            banner = event
            if state == .collapsed { state = .peek }
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.bannerWorkItem = nil
            withAnimation(Motion.panel(self.settings.motion)) {
                self.banner = nil
                if !self.state.isExpanded { self.state = self.idleState }
            }
        }
        bannerWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
    }
}
