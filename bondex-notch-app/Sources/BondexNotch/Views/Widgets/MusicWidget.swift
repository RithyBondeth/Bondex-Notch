import SwiftUI

struct MusicWidget: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var service: NowPlayingService
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        self.environment = environment
        self.service = environment.nowPlaying
        self.settings = environment.settings
    }

    private var accent: Color { settings.effectiveAccent.color }

    var body: some View {
        if service.automationDenied {
            EmptyStateView(
                systemImage: "hand.raised.fill",
                title: "Automation access needed",
                subtitle: "System Settings › Privacy & Security › Automation,\nthen enable Music and Spotify for Bondex Notch."
            )
        } else if let track = service.nowPlaying {
            player(track)
        } else {
            EmptyStateView(
                systemImage: "music.note",
                title: "Nothing playing",
                subtitle: "Start a track in Music or Spotify."
            )
        }
    }

    private func player(_ track: NowPlaying) -> some View {
        HStack(spacing: 14) {
            ArtworkView(image: track.artwork, cornerRadius: 10, tint: accent)
                .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(
                        text: track.title.isEmpty ? "Unknown Track" : track.title,
                        font: .system(size: 13, weight: .semibold)
                    )
                    Text(subtitle(for: track))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }

                progress(track)

                HStack(spacing: 2) {
                    NotchButton(systemImage: "backward.fill", size: 11) { service.previous() }
                    NotchButton(
                        systemImage: track.isPlaying ? "pause.fill" : "play.fill",
                        size: 12,
                        isProminent: true,
                        tint: accent
                    ) {
                        service.playPause()
                    }
                    NotchButton(systemImage: "forward.fill", size: 11) { service.next() }

                    Spacer()

                    AudioBars(isAnimating: track.isPlaying, tint: accent)
                        .opacity(0.9)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtitle(for track: NowPlaying) -> String {
        let parts = [track.artist, track.album].filter { !$0.isEmpty }
        return parts.isEmpty ? track.source.displayName : parts.joined(separator: " — ")
    }

    @ViewBuilder
    private func progress(_ track: NowPlaying) -> some View {
        VStack(spacing: 3) {
            MeterBar(value: track.progress, tint: accent, height: 3)
            HStack {
                Text(track.position.clockString)
                Spacer()
                Text(track.duration.clockString)
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.tertiaryText)
        }
        // Position updates once a second; smooth the bar between samples.
        .animation(.linear(duration: 0.9), value: track.position)
    }
}
