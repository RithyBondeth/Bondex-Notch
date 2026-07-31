import SwiftUI

// MARK: - Tint

private struct NotchTintKey: EnvironmentKey {
    static let defaultValue = Theme.Accent.graphite.color
}

extension EnvironmentValues {
    /// The accent every control in the panel draws with.
    ///
    /// Resolved once at the root — from settings, or from the current album art
    /// when adaptive tinting is on — and read from the environment everywhere
    /// else. The alternative, having each widget ask `SettingsStore` for the
    /// accent itself, means every widget has to learn about artwork too, and
    /// makes it impossible to tell from a call site whether two views will agree
    /// on the colour.
    var notchTint: Color {
        get { self[NotchTintKey.self] }
        set { self[NotchTintKey.self] = newValue }
    }
}

// MARK: - Ambient wash

/// The artwork's colours bled softly into the panel behind its content.
///
/// Two off-centre radial gradients rather than one: a single centred glow reads
/// as a vignette and does not survive the panel changing height, whereas two
/// weighted to opposite corners keeps a sense of direction at any size.
///
/// The drift is a pair of `repeatForever` animations on the gradients' offsets,
/// not a `TimelineView`. Everything in this panel that has been written the
/// timeline way was measured costing single-digit percent CPU *continuously* —
/// see `AudioBars` — because a timeline tick re-evaluates the body and re-renders
/// the panel. Two looping offsets are handed to Core Animation once and cost
/// nothing per frame.
struct AmbientWash: View {

    let palette: ArtworkPalette
    /// Scales the whole effect. The peek is a 40pt strip over the menu bar, where
    /// the full-strength wash of the expanded panel is far too much light.
    var intensity: Double = 1

    @State private var isDrifting = false
    @Environment(\.isRenderingOffscreen) private var isRenderingOffscreen

    var body: some View {
        ZStack {
            // Both weighted low, because the top of the panel is masked out
            // anyway — a blob centred up there would be mostly thrown away.
            blob(
                palette.primary.color,
                alignment: .bottomLeading,
                opacity: 0.38,
                travel: CGSize(width: 26, height: -12),
                period: 11
            )
            blob(
                palette.secondary.color,
                alignment: .trailing,
                opacity: 0.30,
                travel: CGSize(width: -20, height: 16),
                period: 14
            )
        }
        // The gradients are drawn far larger than the panel and clipped by the
        // caller's mask, so their soft edges never land inside the panel — a
        // visible circular edge is the one thing that makes a glow look painted
        // on rather than lit.
        .blur(radius: 26)
        // The top of the panel is where it meets the hardware notch, and that
        // seam only disappears while both are the same black. So the wash is
        // held off the top edge entirely and faded in below it, which also gives
        // the light somewhere to come *from* rather than filling the panel flat.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.5), location: 0.28),
                    .init(color: .black, location: 0.62)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(intensity)
        .allowsHitTesting(false)
        .onAppear { isDrifting = true }
    }

    private func blob(
        _ color: Color,
        alignment: Alignment,
        opacity: Double,
        travel: CGSize,
        period: Double
    ) -> some View {
        RadialGradient(
            colors: [color.opacity(opacity), color.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: 150
        )
        .frame(width: 300, height: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .offset(
            x: isDrifting ? travel.width : 0,
            y: isDrifting ? travel.height : 0
        )
        .animation(
            isRenderingOffscreen
                ? nil
                : .easeInOut(duration: period).repeatForever(autoreverses: true),
            value: isDrifting
        )
    }
}
