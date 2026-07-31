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

    /// The peek is narrower while it is only reporting playback than it is while
    /// carrying a banner, so hit testing has to follow the banner too — otherwise
    /// the panel keeps swallowing clicks in a margin it is no longer drawing.
    var hitRect: CGRect { geometry.hitRect(for: state, hasBanner: banner != nil) }

    // MARK: Pointer

    func pointerMoved(to location: CGPoint) {
        // While expanded, the whole panel keeps it open; while closed, only the
        // notch strip does.
        let liveRect = geometry.hoverRect(for: state, hasBanner: banner != nil)
        let triggerRect = geometry.hoverRect(for: .collapsed)

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
