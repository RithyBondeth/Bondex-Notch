import SwiftUI

/// The compact state: a strip either side of the notch reporting one live thing.
/// Nothing is ever drawn in the middle, where the hardware notch is.
struct PeekView: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var notch: NotchViewModel
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var nowPlaying: NowPlayingService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.notch = environment.notch
        self.settings = environment.settings
        self.nowPlaying = environment.nowPlaying
    }

    private var accent: Color { settings.effectiveAccent.color }
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
        // Centre the content on the menu bar rather than on the panel. Where the
        // peek hangs below the notch — only on displays without one — centring
        // on the panel puts the artwork visibly below the menu bar it belongs
        // to. Flush against a real notch this is zero, and the two agree.
        .padding(.bottom, notch.geometry.peekOverhang(hasBanner: notch.banner != nil))
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
            ArtworkView(image: track.artwork, cornerRadius: 5, tint: accent)
                .frame(width: 21, height: 21)
                .transition(.scale.combined(with: .opacity))
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
