import SwiftUI
import UniformTypeIdentifiers

/// Root of the panel. Draws the silhouette at the size the current state calls
/// for and swaps the content inside it.
///
/// The layout is deliberately arranged so that **nothing inside the panel is
/// re-laid-out while the panel is springing open**. Each state's content is built
/// at its own fixed size and the animating `NotchShape` is used as a *mask* over
/// it, so a frame of the animation costs one path and one composite rather than a
/// full layout pass through every widget, scroll view and text run. Animating the
/// content's own `.frame` instead — the obvious way to write this — makes SwiftUI
/// re-measure the entire subtree 120 times a second, which is what a dropped
/// frame in a notch panel looks like.
struct NotchRootView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var notch: NotchViewModel
    @ObservedObject private var settings: SettingsStore

    /// `ImageRenderer` cannot rasterise `.onDrop`, and substitutes a yellow
    /// placeholder for the whole subtree. The offscreen preview tool sets this to
    /// drop the modifier; it is always false in the running app.
    private let isRenderingOffscreen: Bool

    init(environment: AppEnvironment, isRenderingOffscreen: Bool = false) {
        self.environment = environment
        self.notch = environment.notch
        self.settings = environment.settings
        self.isRenderingOffscreen = isRenderingOffscreen
    }

    private var accent: Color { settings.effectiveAccentColor }
    private var geometry: NotchGeometry { notch.geometry }
    private var state: NotchState { notch.state }

    /// The size the silhouette is animating towards. For the expanded panel this
    /// is measured from the content rather than fixed, so the panel is only as
    /// tall as what it is showing.
    private var contentSize: CGSize { notch.contentSize }

    /// Constant box every state's content is composed inside, so the content
    /// layer's own layout never depends on the animating size.
    private var canvasSize: CGSize { geometry.contentSize(for: .expanded) }

    private var bottomRadius: CGFloat {
        switch state {
        case .collapsed: return Theme.collapsedBottomRadius
        case .peek: return Theme.peekBottomRadius
        case .expanded: return CGFloat(min(max(settings.preferences.bottomCornerRadius, 10), 38))
        }
    }

    /// On a real notch the collapsed panel must be invisible — the hardware is
    /// already black, and drawing fillets there would show two dark tabs sticking
    /// into the menu bar.
    private var silhouetteOpacity: Double {
        (state == .collapsed && geometry.hasHardwareNotch) ? 0 : 1
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                silhouette
                contentLayer
            }
            // The interactive area follows the silhouette, not the constant
            // canvas, so the transparent margins stay click-through.
            .frame(width: contentSize.width, height: contentSize.height, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { notch.toggle() }
            .modifier(ShelfDropModifier(environment: environment, isDisabled: isRenderingOffscreen))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Silhouette

    /// The panel body. Only a shape and its shadow, so it is cheap to animate.
    private var silhouette: some View {
        // One fill for every state: swapping shape styles mid-transition would
        // snap rather than interpolate, and the gradient is subtle enough that a
        // 38pt peek strip just reads as having a defined bottom edge.
        shape
            .fill(Theme.panelFill(
                style: settings.preferences.panelStyle,
                accent: accent,
                opacity: settings.preferences.panelOpacity
            ))
            .overlay {
                if state.isExpanded {
                    shape
                        .fill(Theme.panelGlow(accent: accent))
                        .opacity(settings.preferences.panelStyle == .black ? 0.55 : 1)
                }
            }
            .overlay(shape.stroke(strokeStyle, lineWidth: notch.isDropTargeted ? 1.6 : 1))
            .frame(width: silhouetteWidth, height: contentSize.height)
            .shadow(
                color: .black.opacity(
                    state.isExpanded ? 0.5 * min(max(settings.preferences.shadowStrength, 0), 1) : 0
                ),
                radius: 18,
                y: 8
            )
            .opacity(silhouetteOpacity)
    }

    private var shape: NotchShape {
        NotchShape(flareRadius: flareRadius, bottomRadius: bottomRadius)
    }

    /// The fillets are drawn outside the body, so the shape is wider than the
    /// content by one flare on each side.
    private var flareRadius: CGFloat {
        CGFloat(min(max(settings.preferences.flareRadius, 5), 20))
    }

    private var silhouetteWidth: CGFloat { contentSize.width + flareRadius * 2 }

    private var strokeStyle: AnyShapeStyle {
        notch.isDropTargeted
            ? AnyShapeStyle(accent.opacity(0.9))
            : Theme.panelRim(strength: settings.preferences.rimStrength)
    }

    // MARK: Content

    /// Every state's content, composed inside a constant-size box and revealed by
    /// a mask in the shape of the panel. Because the box never changes size, the
    /// widgets inside it are measured once instead of once per animation frame.
    private var contentLayer: some View {
        ZStack(alignment: .top) {
            content
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
        // Compose the whole layer once, then mask the result. Without this
        // SwiftUI is free to push the mask down into each child and apply it
        // separately.
        .compositingGroup()
        .mask(
            shape
                .frame(width: silhouetteWidth, height: contentSize.height)
                .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
        )
        // A mask only hides; the collapsed panel must not keep swallowing clicks
        // meant for the app underneath.
        .allowsHitTesting(state.isExpanded)
    }

    /// Each state's content at its own fixed size, with the crossfade running on
    /// the shorter `content` curve so text is not still settling after the frame
    /// has arrived.
    @ViewBuilder
    private var content: some View {
        switch state {
        case .collapsed:
            Color.clear
        case .peek:
            PeekView(environment: environment)
                // The peek has two widths — narrow for playback, wider for a
                // banner's text — and its strips are pinned either side of the
                // notch, so the content has to be laid out at whichever is
                // current or the artwork ends up under the mask.
                .frame(width: contentSize.width, height: contentSize.height)
                .transition(peekTransition)
        case .expanded:
            // Fixed width, natural height: the height is the measurement the panel
            // sizes itself from, so it must not be dictated here. Top-aligned in
            // the canvas so the content does not shift as the height settles.
            ExpandedView(environment: environment)
                .frame(width: contentSize.width)
                .frame(maxHeight: canvasSize.height, alignment: .top)
                .onPreferenceChange(ExpandedHeightKey.self) { height in
                    notch.setMeasuredExpandedHeight(height)
                }
                .transition(expandedTransition)
        }
    }

    private var peekTransition: AnyTransition {
        let transition: AnyTransition = reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
        return transition.animation(Motion.content(settings.motion))
    }

    private var expandedTransition: AnyTransition {
        let transition: AnyTransition = reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: -10))
        return transition.animation(Motion.content(settings.motion))
    }
}

private struct ShelfDropModifier: ViewModifier {
    let environment: AppEnvironment
    let isDisabled: Bool

    func body(content: Content) -> some View {
        if isDisabled {
            content
        } else {
            content.onDrop(
                of: ShelfService.acceptedDropTypes,
                delegate: ShelfDropDelegate(environment: environment)
            )
        }
    }
}

/// Drop handling for the shelf, at the panel level so a drag anywhere over the
/// notch opens it.
private struct ShelfDropDelegate: DropDelegate {

    let environment: AppEnvironment

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated { environment.notch.dragEntered() }
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated { environment.notch.dragExited() }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: ShelfService.acceptedDropTypes)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: ShelfService.acceptedDropTypes)
        guard !providers.isEmpty else { return false }

        return MainActor.assumeIsolated {
            environment.notch.isDropTargeted = false

            guard environment.settings.isUnlocked(.shelf),
                  environment.settings.preferences.shelfEnabled else {
                environment.events.post(NotchEvent(
                    kind: .shelf,
                    title: "Drop Shelf is a Pro feature",
                    subtitle: "Add a license key in Settings"
                ))
                return false
            }

            Task { @MainActor in
                let urls = await environment.shelf.resolve(providers: providers)
                guard !urls.isEmpty else {
                    Log.shelf.error("Drop had supported types but no usable file or image data")
                    environment.notch.dragExited()
                    return
                }
                environment.shelf.add(urls: urls)
                environment.notch.tab = .shelf
                environment.notch.expand()
                environment.notch.setPinned(true)
            }
            return true
        }
    }
}
