import AppKit
import SwiftUI

/// Carries the expanded content's laid-out height up to the panel.
struct ExpandedHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The full panel: a tab strip along the top and one widget below it.
struct ExpandedView: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var notch: NotchViewModel
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        self.environment = environment
        self.notch = environment.notch
        self.settings = environment.settings
    }

    @Environment(\.notchTint) private var accent

    /// Ties the chips' backgrounds together into one pill that slides between
    /// them, instead of one capsule fading out as the next fades in.
    @Namespace private var pill

    /// Keeps the tab strip clear of the hardware notch, which sits over the top
    /// centre of the panel.
    private var topInset: CGFloat { notch.geometry.notchSize.height + 4 }

    var body: some View {
        VStack(spacing: 10) {
            header
            // A system `Divider` renders as a light separator tuned for a light
            // window; on a near-black panel it reads as a bright scratch.
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
            widget
                .frame(maxWidth: .infinity)
                // nil height means "as tall as the content" — that is what makes
                // the panel itself size to what it is showing.
                .frame(height: notch.tab.widgetHeight)
                // Swapping tabs is a content change, so it gets the content
                // curve rather than the panel's.
                .animation(Motion.content(settings.motion), value: notch.tab)
        }
        .padding(.top, topInset)
        .padding(.horizontal, Theme.contentPadding)
        .padding(.bottom, Theme.contentPadding)
        .foregroundStyle(Theme.primaryText)
        // Report the height this content actually needs, so the panel can be
        // drawn at exactly that size rather than at a one-size-fits-all maximum.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ExpandedHeightKey.self, value: proxy.size.height)
            }
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            ForEach(environment.availableTabs) { tab in
                TabChip(
                    tab: tab,
                    isSelected: notch.tab == tab,
                    isLocked: tab.requiredFeature.map { !settings.isUnlocked($0) } ?? false,
                    accent: accent,
                    namespace: pill
                ) {
                    withAnimation(Motion.content(settings.motion)) { notch.tab = tab }
                }
            }

            Spacer(minLength: 6)

            NotchButton(systemImage: "xmark", size: 10, tint: Theme.secondaryText) {
                notch.collapse()
            }
        }
        // Tabs are also reachable from the trackpad. Hitting the strip means
        // travelling to the very top of the screen and then aiming at a 20pt
        // row; a two-finger swipe anywhere across it is a much shorter path to
        // the same place, and the strip has no scroll view of its own to fight
        // over the gesture.
        .modifier(TabScrubGesture(
            tabs: environment.availableTabs,
            selection: $notch.tab,
            animation: Motion.content(settings.motion)
        ))
    }

    // MARK: Widget

    @ViewBuilder
    private var widget: some View {
        if let feature = notch.tab.requiredFeature, !settings.isUnlocked(feature) {
            LockedFeatureView(feature: feature, tint: accent)
        } else {
            switch notch.tab {
            case .home:
                HomeWidget(environment: environment)
            case .music:
                MusicWidget(environment: environment)
            case .files:
                FileActivityWidget(environment: environment)
            case .activity:
                ActivityWidget(environment: environment)
            case .shelf:
                ShelfWidget(environment: environment)
            }
        }
    }
}

// MARK: - Tab chip

private struct TabChip: View {
    let tab: NotchTab
    let isSelected: Bool
    let isLocked: Bool
    let accent: Color
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isLocked ? "lock.fill" : tab.systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                if isSelected {
                    Text(tab.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .fixedSize()
                        // Width, not opacity: the label has to push the
                        // neighbouring chips aside as it appears, or the strip
                        // jumps a whole label's width in one frame.
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(Motion.hover.delay(0.06)),
                                removal: .opacity.animation(.linear(duration: 0.05))
                            )
                        )
                }
            }
            .foregroundStyle(isSelected ? Color.black : Theme.secondaryText)
            .padding(.horizontal, isSelected ? 9 : 7)
            .padding(.vertical, 5)
            .background(background)
            .contentShape(Capsule())
            .animation(Motion.hover, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    /// The selected chip's fill is a *single* view shared across the whole strip
    /// via `matchedGeometryEffect`, so switching tabs slides one pill from the
    /// old chip to the new one. Giving each chip its own capsule and animating
    /// the colour instead crossfades two stationary shapes, which loses the only
    /// thing the animation was for: showing where the selection went.
    @ViewBuilder
    private var background: some View {
        if isSelected {
            Capsule(style: .continuous)
                .fill(accent)
                .matchedGeometryEffect(id: "selection", in: namespace)
        } else {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.14 : 0.06))
        }
    }
}

// MARK: - Swipe to change tabs

/// Turns a horizontal two-finger swipe over the panel into a tab change.
///
/// A trackpad swipe arrives as a scroll wheel event, which SwiftUI has no
/// modifier for — `DragGesture` only sees a click-and-drag, which this is not.
/// The obvious AppKit answer, an `NSView` overlaid on the strip to catch
/// `scrollWheel`, cannot work here: scroll events are routed by hit testing, so
/// a view positioned to receive them is also positioned to swallow the clicks
/// that select a chip.
///
/// A local event monitor sidesteps the hierarchy entirely. It sees the events
/// the app is about to dispatch, without being in the way of anything, and it is
/// filtered to the notch panel so a scroll over the Settings window is left
/// alone. The event is returned unconsumed, so the widget below still scrolls.
private struct TabScrubGesture: ViewModifier {
    let tabs: [NotchTab]
    @Binding var selection: NotchTab
    let animation: Animation

    /// Distance a swipe has to cover before it counts as a tab change. Below
    /// this, the tail end of a scroll aimed at a list would keep changing tabs.
    private static let threshold: CGFloat = 26

    @State private var monitor: Any?
    /// A trackpad emits a stream of small deltas, so one gesture would otherwise
    /// skip several tabs. Reset the moment the threshold is crossed, and again
    /// when the fingers lift.
    @State private var accumulated: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onAppear(perform: install)
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { handle(event) }
            return event
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.window is NotchPanel else { return }
        // A mostly-vertical scroll belongs to whatever list is under the pointer.
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5 else { return }

        if event.phase.contains(.began) || event.phase.contains(.ended) {
            accumulated = 0
        }
        accumulated += event.scrollingDeltaX
        guard abs(accumulated) >= Self.threshold else { return }

        let forward = accumulated < 0
        accumulated = 0
        step(forward: forward)
    }

    private func step(forward: Bool) {
        guard let current = tabs.firstIndex(of: selection) else { return }
        // Natural scrolling: pushing the content leftwards moves forward, the
        // same direction as flicking through pages.
        let next = current + (forward ? 1 : -1)
        guard tabs.indices.contains(next) else { return }
        withAnimation(animation) { selection = tabs[next] }
    }
}
