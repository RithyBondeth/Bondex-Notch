import SwiftUI

/// The default tab: a one-line media row over the system gauges. This is what
/// most sessions will only ever see, so it has to answer "what is happening
/// right now" without a click.
struct HomeWidget: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var nowPlaying: NowPlayingService
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        self.environment = environment
        self.nowPlaying = environment.nowPlaying
        self.settings = environment.settings
    }

    private var accent: Color { settings.effectiveAccent.color }

    var body: some View {
        VStack(spacing: 10) {
            if settings.preferences.musicWidgetEnabled {
                mediaRow
            }
            if settings.preferences.systemWidgetEnabled {
                SystemWidget(environment: environment, compact: true)
            }
            if !settings.preferences.musicWidgetEnabled
                && !settings.preferences.systemWidgetEnabled {
                EmptyStateView(
                    systemImage: "square.grid.2x2",
                    title: "No widgets enabled",
                    subtitle: "Turn some on in Settings."
                )
            }
        }
    }

    @ViewBuilder
    private var mediaRow: some View {
        if let track = nowPlaying.nowPlaying {
            HStack(spacing: 10) {
                ArtworkView(image: track.artwork, cornerRadius: 7, tint: accent)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(
                        text: track.title.isEmpty ? "Unknown Track" : track.title,
                        font: .system(size: 12, weight: .semibold)
                    )
                    Text(track.artist.isEmpty ? track.source.displayName : track.artist)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                NotchButton(systemImage: "backward.fill", size: 10) {
                    nowPlaying.previous()
                }
                NotchButton(
                    systemImage: track.isPlaying ? "pause.fill" : "play.fill",
                    size: 11,
                    isProminent: true,
                    tint: accent
                ) {
                    nowPlaying.playPause()
                }
                NotchButton(systemImage: "forward.fill", size: 10) {
                    nowPlaying.next()
                }
            }
            .notchCard()
        } else {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
                Text(nowPlaying.automationDenied
                     ? "Automation access needed for media control"
                     : "Nothing playing")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
            }
            .notchCard()
        }
    }
}
