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
    @ObservedObject private var meetings: UpcomingMeetingService
    @ObservedObject private var focusTimer: FocusTimerService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.nowPlaying = environment.nowPlaying
        self.settings = environment.settings
        self.agents = environment.agents
        self.liveActivities = environment.liveActivities
        self.meetings = environment.meetings
        self.focusTimer = environment.focusTimer
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

    /// A session in progress is live, so it leads the tab; an idle timer is
    /// only an option, and gets a chip at the foot instead.
    private var showsFocusCard: Bool {
        settings.preferences.focusTimerEnabled && focusTimer.snapshot.isActive
    }

    private var showsFocusChip: Bool {
        settings.preferences.focusTimerEnabled && !focusTimer.snapshot.isActive
    }

    private var showsMeeting: Bool {
        settings.preferences.upcomingMeetingsEnabled
            && meetings.meeting?.isRelevantToHome() == true
    }

    private var showsLive: Bool {
        settings.isTabEnabled(.live) && !liveActivities.active.isEmpty
    }

    private var showsSystemSummary: Bool {
        settings.isTabEnabled(.system) && settings.preferences.showSystemSummaryOnHome
    }

    var body: some View {
        VStack(spacing: Theme.widgetSpacing) {
            if showsFocusCard {
                FocusTimerCard(environment: environment)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if showsMeeting {
                UpcomingMeetingCard(environment: environment)
            }
            if showsLive {
                LiveActivityCard(environment: environment)
            }
            if showsAgents {
                AgentActivityCard(environment: environment)
            }
            if settings.isTabEnabled(.music) {
                mediaRow
            }
            if showsSystemSummary {
                SystemWidget(environment: environment, compact: true)
            }
            if showsFocusChip {
                HStack {
                    FocusStartChip(environment: environment)
                    Spacer()
                }
                .transition(.opacity)
            }
            if !showsFocusCard, !showsFocusChip, !showsMeeting, !showsLive, !showsAgents,
               !settings.isTabEnabled(.music), !showsSystemSummary {
                EmptyStateView(
                    systemImage: "square.grid.2x2",
                    title: "No widgets enabled",
                    subtitle: "Turn some on in Settings."
                )
            }
        }
        .animation(Motion.content(settings.motion), value: focusTimer.snapshot.isActive)
    }

    @ViewBuilder
    private var mediaRow: some View {
        if let track = nowPlaying.nowPlaying {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ArtworkView(image: track.artwork, cornerRadius: 8, tint: accent)
                        .frame(
                            width: track.source.isBrowser ? 68 : 44,
                            height: 44
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title.isEmpty ? "Unknown Track" : track.title)
                            .font(.system(size: Theme.TextSize.title, weight: .semibold))
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
                        .font(.system(size: Theme.TextSize.footnote, weight: .medium))
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
                    // Advanced from the sample's timestamp rather than stepped
                    // by each poll: the service no longer republishes a track
                    // just because its position moved on by a second.
                    TimelineView(.animation(minimumInterval: 1, paused: !track.isPlaying)) { timeline in
                        let progress = track.progress(at: timeline.date)
                        MeterBar(value: progress, tint: accent, height: 2)
                            .animation(.linear(duration: 1), value: progress)
                            .accessibilityLabel("Playback progress")
                            .accessibilityValue("\(Int(progress * 100)) percent")
                    }
                }
            }
            .notchCard(padding: 10)
        } else {
            HStack(spacing: 8) {
                Image(systemName: idleIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
                Text(idleMessage)
                    .font(.system(size: Theme.TextSize.body))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer()
                // Home is where hovering the notch lands, so the fix is one
                // click from here rather than a tab the user has to find.
                if nowPlaying.blockedOnMediaSite, nowPlaying.blockedBrowser?.mediaAccessFix != nil {
                    PillButton(title: "Fix", systemImage: nil, tint: accent, isProminent: true) {
                        withAnimation(Motion.content(settings.motion)) {
                            environment.notch.tab = .music
                        }
                    }
                }
            }
            .notchCard(padding: Theme.compactCardPadding)
        }
    }

    private var idleIcon: String {
        if nowPlaying.automationDenied { return "hand.raised.fill" }
        if nowPlaying.blockedOnMediaSite { return "play.rectangle.on.rectangle" }
        return "music.note"
    }

    /// One line, so it has to say what to do rather than explain why.
    private var idleMessage: String {
        if nowPlaying.automationDenied {
            return "Automation access needed for media control"
        }
        // Only when a media site is open there: a browser that refuses on a
        // docs page is not hiding anything the user is waiting for.
        if nowPlaying.blockedOnMediaSite, let browser = nowPlaying.blockedBrowser {
            return "\(browser.displayName) is hiding what’s playing"
        }
        return "Nothing playing"
    }
}
