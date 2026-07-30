import SwiftUI

/// The compact state: a strip either side of the notch reporting one live
/// thing. Nothing is ever drawn in the middle, where the hardware notch is.
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
                .padding(.leading, 10)

            // Reserved for the hardware notch.
            Color.clear.frame(width: notchWidth)

            trailing
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 10)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Leading

    @ViewBuilder
    private var leading: some View {
        if let banner = notch.banner {
            Image(systemName: banner.kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(banner.kind.tint)
                .transition(.scale.combined(with: .opacity))
        } else if let track = nowPlaying.nowPlaying {
            ArtworkView(image: track.artwork, cornerRadius: 5, tint: accent)
                .frame(width: 20, height: 20)
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
            .frame(maxWidth: 130, alignment: .trailing)
            .transition(.opacity)
        } else if let track = nowPlaying.nowPlaying {
            AudioBars(isAnimating: track.isPlaying, tint: accent)
                .transition(.opacity)
        }
    }
}
