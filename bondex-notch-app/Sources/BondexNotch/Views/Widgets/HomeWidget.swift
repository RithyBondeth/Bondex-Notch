import SwiftUI

/// The default tab: a one-line media row over the system gauges. This is what
/// most sessions will only ever see, so it has to answer "what is happening
/// right now" without a click.
struct HomeWidget: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var nowPlaying: NowPlayingService
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var agents: AgentActivityService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.nowPlaying = environment.nowPlaying
        self.settings = environment.settings
        self.agents = environment.agents
    }

    private var accent: Color { settings.effectiveAccentColor }

    /// Agents get the top of the tab whenever any are working.
    ///
    /// Above the media row on purpose: an agent run is the transient thing on
    /// this tab. Music will still be playing in ten minutes and is reported by
    /// the peek's artwork anyway, while a run you opened the panel to check on
    /// might be over by the time you look again.
    private var showsAgents: Bool {
        settings.preferences.agentActivityEnabled && !agents.active.isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            if showsAgents {
                AgentActivityCard(environment: environment)
            }
            if settings.preferences.musicWidgetEnabled {
                mediaRow
            }
            if settings.preferences.systemWidgetEnabled {
                SystemWidget(environment: environment, compact: true)
            }
            if !showsAgents
                && !settings.preferences.musicWidgetEnabled
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
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(
                        text: track.title.isEmpty ? "Unknown Track" : track.title,
                        font: .system(size: 12, weight: .semibold)
                    )
                    Text(track.artist.isEmpty
                         ? track.source.displayName
                         : "\(track.artist) · \(track.source.displayName)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if track.supportsTransport {
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
                } else {
                    AudioBars(isAnimating: track.isPlaying, tint: accent)
                        .padding(.trailing, 4)
                }
            }
            .notchCard(padding: Theme.compactCardPadding)
        } else {
            HStack(spacing: 8) {
                Image(systemName: idleIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
                Text(idleMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer()
            }
            .notchCard(padding: Theme.compactCardPadding)
        }
    }

    private var idleIcon: String {
        if nowPlaying.automationDenied { return "hand.raised.fill" }
        if nowPlaying.blockedBrowser != nil { return "curlybraces" }
        return "music.note"
    }

    /// One line, so it has to say what to do rather than explain why.
    private var idleMessage: String {
        if nowPlaying.automationDenied {
            return "Automation access needed for media control"
        }
        if let browser = nowPlaying.blockedBrowser {
            return "Allow JavaScript from Apple Events in \(browser.displayName)"
        }
        return "Nothing playing"
    }
}
