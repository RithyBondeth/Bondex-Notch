import SwiftUI

/// The compact state: a strip either side of the notch reporting one live thing.
/// Nothing is ever drawn in the middle, where the hardware notch is.
struct PeekView: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var notch: NotchViewModel
    @ObservedObject private var nowPlaying: NowPlayingService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.notch = environment.notch
        self.nowPlaying = environment.nowPlaying
    }

    @Environment(\.notchTint) private var accent
    private var notchWidth: CGFloat { notch.geometry.notchSize.width }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 11)

            // Reserved for the hardware notch.
            Color.clear.frame(width: notchWidth)

            trailing
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 11)
        }
        // The peek hangs a few points below the menu bar; centre content on the
        // menu bar itself rather than on the panel, or it sits visibly low.
        .padding(.bottom, 6)
        .frame(maxHeight: .infinity)
    }

    // MARK: Leading

    @ViewBuilder
    private var leading: some View {
        if let banner = notch.banner {
            Image(systemName: banner.kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(banner.kind.tint)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(banner.kind.tint.opacity(0.16))
                )
                .transition(.scale.combined(with: .opacity))
        } else if let track = nowPlaying.nowPlaying {
            artwork(track)
                .transition(.scale.combined(with: .opacity))
        }
    }

    /// Album art with the track's progress drawn around it.
    ///
    /// The peek's whole job is to answer "what is playing" without a click, and
    /// how far through it is is the one other thing worth knowing at a glance —
    /// but there is no room beside the notch for a bar and two clocks. A ring
    /// around art that is already there costs no width at all.
    @ViewBuilder
    private func artwork(_ track: NowPlaying) -> some View {
        let art = ArtworkView(image: track.artwork, cornerRadius: 5, tint: accent)
            .frame(width: 21, height: 21)

        if track.isLive || track.duration <= 0 {
            // A stream has no end to be a fraction of, and a full ring would
            // claim it was about to finish.
            art
        } else {
            // Ticked once a second, not at the 15Hz the expanded player uses.
            // The peek is on screen for as long as anything is playing, and a
            // timeline tick re-renders the panel — at this size a second's worth
            // of a three-minute track is a third of a degree of arc, so the
            // faster schedule would buy nothing visible for a permanent cost.
            TimelineView(.animation(minimumInterval: 1, paused: !track.isPlaying)) { timeline in
                art.overlay(
                    ProgressRing(
                        value: track.progress(at: timeline.date),
                        tint: accent,
                        lineWidth: 1.6
                    )
                    .padding(-3.5)
                )
            }
        }
    }

    // MARK: Trailing

    @ViewBuilder
    private var trailing: some View {
        if let banner = notch.banner {
            VStack(alignment: .trailing, spacing: 0) {
                Text(banner.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                if let subtitle = banner.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 150, alignment: .trailing)
            .transition(.opacity)
        } else if let track = nowPlaying.nowPlaying {
            // Artwork and equaliser only. The title lives one hover away in the
            // expanded panel; putting it here too made the peek a wide slab of
            // text sitting over the menu bar all day.
            AudioBars(isAnimating: track.isPlaying, tint: accent)
                .transition(.opacity)
        }
    }
}
