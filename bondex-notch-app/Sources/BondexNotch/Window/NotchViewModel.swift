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
    @Published var tab: NotchTab = .home {
        willSet {
            // Before the change is published, so the view that renders the new
            // tab already knows which side it slides in from.
            let from = tabOrder.firstIndex(of: tab) ?? 0
            let to = tabOrder.firstIndex(of: newValue) ?? 0
            tabAdvances = to >= from
        }
    }
    /// The strip's left-to-right order, kept in step by the environment.
    var tabOrder: [NotchTab] = NotchTab.allCases
    /// Whether the last tab change moved right along the strip.
    private(set) var tabAdvances = true
    @Published var isDropTargeted = false
    /// Set while a transient banner (track change, download finished) is showing.
    @Published private(set) var banner: NotchEvent?
    /// Short-lived feedback for hardware keys. This intentionally does not enter
    /// the activity feed: changing volume is interaction feedback, not history.
    @Published private(set) var systemHUD: SystemHUDPresentation?
    @Published var privacyActivity = PrivacyActivityState() {
        didSet {
            guard privacyActivity.isActive != oldValue.isActive else { return }
            refreshIdleState()
        }
    }

    @Published private(set) var geometry: NotchGeometry

    /// Latched open by a click, so the panel stays put while the user works in it.
    private var isPinned = false
    /// The panel has keyboard focus — someone is typing in Quick Capture, a
    /// search field or the palette. The pointer drifting off the panel mid-word
    /// must not close it; a click elsewhere, which takes the focus away, does.
    private var holdsOpenForKeyboard = false
    private var closeWorkItem: DispatchWorkItem?
    private var openWorkItem: DispatchWorkItem?
    private var bannerWorkItem: DispatchWorkItem?
    private var systemHUDWorkItem: DispatchWorkItem?
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

    /// How many coding agents a hook reports working, which the peek shows with
    /// a mark and a clock each. Kept separate from `hasLiveActivity` because it
    /// also decides how *wide* the peek has to be: playback needs room for
    /// artwork and an equaliser, and each agent brings its own pair.
    ///
    /// Only *working* agents reach the peek. One that is merely open — a
    /// process is running, but no hook says it is doing anything — is listed in
    /// the expanded panel and nowhere else. The Claude and ChatGPT desktop apps
    /// each carry an agent binary, so "open" is true for as long as either app
    /// is, and letting it hold the peek kept a still mark and the word "Open"
    /// over the menu bar all day, telling you nothing.
    ///
    /// A working agent outranks playback — the run is the transient thing you
    /// want to see the end of, and music will still be playing in ten minutes.
    @Published var workingAgentCount = 0 {
        didSet {
            // Only the empty/non-empty transition changes whether the peek is up
            // at all; going from one agent to two just resizes it, which the
            // published change already animates.
            guard (workingAgentCount > 0) != (oldValue > 0) else { return }
            refreshIdleState()
        }
    }

    /// Whether playback gets the peek, by its own preference.
    var showsMediaInPeek: Bool { hasLiveActivity && settings.preferences.peekWhilePlaying }

    @Published var customLiveActivityCount = 0 {
        didSet {
            guard (customLiveActivityCount > 0) != (oldValue > 0) else { return }
            refreshIdleState()
        }
    }

    var hasFocusTimer = false {
        didSet {
            guard hasFocusTimer != oldValue else { return }
            refreshIdleState()
        }
    }

    var hasUpcomingMeeting = false {
        didSet {
            guard hasUpcomingMeeting != oldValue else { return }
            refreshIdleState()
        }
    }

    /// What the peek is carrying, which is what decides its width — and, since
    /// `PeekView` renders from this, what it shows.
    ///
    /// Direct hardware feedback outranks a banner, which outranks live progress,
    /// agents and playback: the more immediate signal gets the limited space.
    ///
    /// Each source is gated by its own preference *here*, the same way
    /// `idleState` gates it. They used to disagree: the meeting service also
    /// runs for Smart Profiles with "Upcoming meetings" switched off, and an
    /// ungated meeting then took over a peek that was open for playback.
    var peekContent: PeekContent {
        if systemHUD != nil { return .systemHUD }
        if privacyActivity.isActive { return .privacy }
        if banner != nil { return .banner }
        if showsFocusTimer { return .focus }
        if showsUpcomingMeeting { return .meeting }
        if showsLiveActivities { return .live }
        if showsAgents { return .agent(agents: workingAgentCount) }
        return .media
    }

    private var showsFocusTimer: Bool {
        hasFocusTimer && settings.preferences.focusTimerEnabled
    }

    private var showsUpcomingMeeting: Bool {
        hasUpcomingMeeting && settings.preferences.upcomingMeetingsEnabled
    }

    /// The live-activity watcher runs while the Live tab is enabled, which a
    /// Smart Profile can decide independently of the global preference.
    private var showsLiveActivities: Bool {
        customLiveActivityCount > 0 && settings.isTabEnabled(.live)
    }

    /// An agent working is not gated behind the *media* peek preference —
    /// someone who turned off "peek while playing" was asking not to see album
    /// art over the menu bar, which says nothing about whether they want to know
    /// their agent is still running.
    private var showsAgents: Bool {
        workingAgentCount > 0 && settings.preferences.agentActivityEnabled
    }

    init(settings: SettingsStore, events: EventCenter, screen: NSScreen) {
        self.settings = settings
        self.events = events
        self.geometry = NotchGeometry.measure(screen: screen)

        events.$latest
            .compactMap { $0 }
            .sink { [weak self] event in self?.show(banner: event) }
            .store(in: &cancellables)

        // `idleState` reads several feature preferences back out of the store,
        // so this has to run after the new value is stored, not from `willSet`.
        settings.preferencesDidChange
            .sink { [weak self] _ in self?.refreshIdleState() }
            .store(in: &cancellables)
        settings.activeProfileDidChange
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
            return geometry.contentSize(for: state, peek: peekContent)
        }
        let maximum = NotchGeometry.expandedContentSize
        let measured = measuredExpandedHeight ?? maximum.height
        return CGSize(
            width: min(max(settings.effectivePanelWidth, 440), maximum.width),
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

        if state.isExpanded {
            if NotchGeometry.pointer(location, isIn: liveRect) {
                cancelPendingClose()
            } else if !isPinned, !holdsOpenForKeyboard {
                scheduleClose()
            }
            return
        }

        guard settings.preferences.expandOnHover else {
            cancelPendingOpen()
            return
        }

        if NotchGeometry.pointer(location, isIn: triggerRect)
            || NotchGeometry.pointer(location, isIn: liveRect) {
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
            systemHUD = nil
        }
    }

    func collapse() {
        isPinned = false
        holdsOpenForKeyboard = false
        cancelPendingOpen()
        cancelPendingClose()
        withAnimation(Motion.panel(settings.motion)) {
            state = idleState
        }
    }

    /// Open-and-latch, or close: the global shortcut and the menu-bar item.
    func toggle() {
        if state.isExpanded {
            collapse()
        } else {
            isPinned = true
            expand()
        }
    }

    /// A click on the panel itself.
    ///
    /// On the notch or a peek it opens and latches. On the open panel it only
    /// latches: every click that missed a control — card padding, a label, a
    /// gauge, the gap between list rows — used to fall through to `toggle()`
    /// and slam the panel shut under the pointer. Closing is the close button,
    /// Escape, the shortcut, or a click anywhere outside the panel.
    func panelTapped() {
        isPinned = true
        cancelPendingClose()
        guard !state.isExpanded else { return }
        expand()
    }

    /// A click somewhere else on screen while the panel is open.
    func clickedOutside() {
        guard state.isExpanded, !isDropTargeted else { return }
        collapse()
    }

    /// Reported by the window controller as the panel gains and loses keyboard
    /// focus.
    func setHoldsOpenForKeyboard(_ holds: Bool) {
        guard holdsOpenForKeyboard != holds else { return }
        holdsOpenForKeyboard = holds
        if holds { cancelPendingClose() }
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        if !pinned { scheduleClose() }
    }

    func dragEntered() {
        isDropTargeted = true
        // `isTabEnabled`, not the raw preference: a Smart Profile without the
        // shelf would otherwise switch to a tab that has no chip in the strip.
        guard settings.isTabEnabled(.shelf) else { return }
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
        if systemHUD != nil || banner != nil { return .peek }
        if privacyActivity.isActive { return .peek }
        if showsFocusTimer || showsUpcomingMeeting || showsLiveActivities || showsAgents {
            return .peek
        }
        return showsMediaInPeek ? .peek : .collapsed
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
            guard !self.isPinned, !self.holdsOpenForKeyboard else { return }
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

    func show(systemHUD presentation: SystemHUDPresentation) {
        guard settings.preferences.systemHUDEnabled, !state.isExpanded else { return }

        systemHUDWorkItem?.cancel()
        let resizes = state == .collapsed || peekContent != .systemHUD
        withAnimation(resizes ? Motion.panel(settings.motion) : Motion.content(settings.motion)) {
            systemHUD = presentation
            if state == .collapsed { state = .peek }
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.systemHUDWorkItem = nil
            withAnimation(Motion.panel(self.settings.motion)) {
                self.systemHUD = nil
                if !self.state.isExpanded { self.state = self.idleState }
            }
        }
        systemHUDWorkItem = work
        let duration = min(max(settings.preferences.systemHUDDuration, 0.8), 5)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func show(banner event: NotchEvent) {
        // Playback reaches the feed but never the banner; see `deservesBanner`.
        guard event.kind.deservesBanner else { return }

        // Never interrupt the expanded panel with a banner; the feed already
        // shows it there.
        guard !state.isExpanded else { return }

        bannerWorkItem?.cancel()
        // Growing out of the notch, or widening a playback or agent strip to
        // banner width, is a panel move; swapping one banner for the next
        // inside a banner-width peek is only a content change. Treating the
        // widening as content ran the silhouette on the quick content curve
        // while the panel's own moves use the spring.
        let resizes = state == .collapsed || peekContent != .banner
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
