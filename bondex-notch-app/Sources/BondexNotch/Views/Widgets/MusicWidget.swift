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

    @Environment(\.notchTint) private var accent

    var body: some View {
        if let track = service.nowPlaying {
            player(track)
        } else if service.automationDenied {
            EmptyStateView(
                systemImage: "hand.raised.fill",
                title: "Automation access needed",
                subtitle: "System Settings › Privacy & Security › Automation,\nthen enable the players you use for Bondex Notch."
            )
        } else if let browser = service.blockedBrowser {
            // The one thing the user has to do by hand for web media to appear.
            // Saying nothing here is what "YouTube shows nothing" feels like.
            EmptyStateView(
                systemImage: "curlybraces",
                title: "Turn on JavaScript from Apple Events",
                subtitle: browser.javaScriptHint
            )
        } else {
            EmptyStateView(
                systemImage: "music.note",
                title: "Nothing playing",
                subtitle: "Start something in Music, Spotify, or a browser tab."
            )
        }
    }

    private func player(_ track: NowPlaying) -> some View {
        HStack(spacing: 14) {
            ArtworkView(image: track.artwork, cornerRadius: 10, tint: accent)
                .frame(width: 78, height: 78)
                // A cover sitting directly on black has nothing holding it to the
                // panel. A shadow in its own dominant colour reads as the art
                // lighting the surface it is on, which is the same idea as the
                // panel's ambient wash at a scale you notice up close.
                .shadow(color: accent.opacity(0.34), radius: 14, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(
                        text: track.title.isEmpty ? "Unknown Track" : track.title,
                        font: .system(size: 13, weight: .semibold)
                    )
                    HStack(spacing: 5) {
                        Text(subtitle(for: track))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                        sourceBadge(track)
                    }
                }

                progress(track)

                HStack(spacing: 2) {
                    if track.supportsTransport {
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
                    } else {
                        // Read from the window title: visible, but not drivable.
                        Text("Playing in \(track.source.displayName)")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }

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

    /// Names where the audio is coming from. With browsers in the mix there can
    /// be several plausible sources, so "Chrome" is genuinely useful information.
    @ViewBuilder
    private func sourceBadge(_ track: NowPlaying) -> some View {
        Text(track.source.displayName)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                Capsule(style: .continuous).fill(Color.white.opacity(0.09))
            )
            .fixedSize()
    }

    @ViewBuilder
    private func progress(_ track: NowPlaying) -> some View {
        if track.isLive {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
                Text("Live")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
            }
            .frame(height: 16)
        } else {
            // Playback is polled once a second, so the position is advanced from
            // the sample's timestamp instead of being stepped. A 15Hz timeline
            // recomputing the real position beats animating between one-second
            // jumps: it stays correct through a seek, and it costs nothing while
            // paused because the schedule stops.
            TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !track.isPlaying)) { timeline in
                let position = track.position(at: timeline.date)
                VStack(spacing: 3) {
                    MeterBar(
                        value: track.duration > 0 ? position / track.duration : 0,
                        tint: accent,
                        height: 3
                    )
                    HStack {
                        Text(position.clockString)
                        Spacer()
                        Text(track.duration.clockString)
                    }
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
    }
}
