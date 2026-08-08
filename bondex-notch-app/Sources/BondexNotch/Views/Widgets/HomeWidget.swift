import SwiftUI

/// The default tab: live agents and media, plus an optional compact copy of the
/// dedicated System tab. Users who want a quieter Home can keep every metric in
/// System; users who prefer a dashboard can opt the summary back in.
struct HomeWidget: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var nowPlaying: NowPlayingService
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var agents: AgentActivityService
    @ObservedObject private var liveActivities: LiveActivityService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.nowPlaying = environment.nowPlaying
        self.settings = environment.settings
        self.agents = environment.agents
        self.liveActivities = environment.liveActivities
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
            if settings.preferences.customLiveActivitiesEnabled,
               !liveActivities.active.isEmpty {
                LiveActivityCard(environment: environment)
            }
            if showsAgents {
                AgentActivityCard(environment: environment)
            }
            if settings.preferences.musicWidgetEnabled {
                mediaRow
            }
            if settings.preferences.systemWidgetEnabled
                && settings.preferences.showSystemSummaryOnHome {
                SystemWidget(environment: environment, compact: true)
            }
            if !showsAgents
                && liveActivities.active.isEmpty
                && !settings.preferences.musicWidgetEnabled
                && !(settings.preferences.systemWidgetEnabled
                     && settings.preferences.showSystemSummaryOnHome) {
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
            VStack(spacing: 9) {
                HStack(spacing: 12) {
                    ArtworkView(image: track.artwork, cornerRadius: 8, tint: accent)
                        .frame(
                            width: track.source.isBrowser ? 78 : 48,
                            height: 48
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title.isEmpty ? "Unknown Track" : track.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 5) {
                            if !track.artist.isEmpty {
                                Text(track.artist)
                                    .lineLimit(1)
                                Circle()
                                    .fill(Theme.tertiaryText)
                                    .frame(width: 2, height: 2)
                            }
                            Text(track.source.displayName)
                                .lineLimit(1)
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    }

                    if track.supportsTransport {
                        HStack(spacing: 2) {
                            NotchButton(systemImage: "backward.fill", size: 10) {
                                nowPlaying.previous()
                            }
                            .accessibilityLabel("Previous")

                            NotchButton(
                                systemImage: track.isPlaying ? "pause.fill" : "play.fill",
                                size: 12,
                                isProminent: true,
                                tint: accent
                            ) {
                                nowPlaying.playPause()
                            }
                            .accessibilityLabel(track.isPlaying ? "Pause" : "Play")

                            NotchButton(systemImage: "forward.fill", size: 10) {
                                nowPlaying.next()
                            }
                            .accessibilityLabel("Next")
                        }
                        .fixedSize()
                    } else {
                        AudioBars(isAnimating: track.isPlaying, tint: accent)
                            .padding(.trailing, 4)
                    }
                }

                if !track.isLive {
                    MeterBar(value: track.progress, tint: accent, height: 2)
                        .accessibilityLabel("Playback progress")
                        .accessibilityValue("\(Int(track.progress * 100)) percent")
                }
            }
            .notchCard(padding: 10)
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
