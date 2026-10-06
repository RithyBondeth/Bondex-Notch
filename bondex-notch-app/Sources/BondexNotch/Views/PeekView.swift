import SwiftUI

/// The compact state: a strip either side of the notch reporting one live thing.
/// Nothing is ever drawn in the middle, where the hardware notch is.
struct PeekView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var notch: NotchViewModel
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var nowPlaying: NowPlayingService
    @ObservedObject private var agents: AgentActivityService
    @ObservedObject private var liveActivities: LiveActivityService
    @ObservedObject private var focusTimer: FocusTimerService
    @ObservedObject private var meetings: UpcomingMeetingService
    @ObservedObject private var privacyActivity: PrivacyActivityService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.notch = environment.notch
        self.settings = environment.settings
        self.nowPlaying = environment.nowPlaying
        self.agents = environment.agents
        self.liveActivities = environment.liveActivities
        self.focusTimer = environment.focusTimer
        self.meetings = environment.meetings
        self.privacyActivity = environment.privacyActivity
    }

    private var accent: Color { settings.effectiveAccentColor }
    private var notchWidth: CGFloat { notch.geometry.notchSize.width }

    /// The agents the peek is reporting: the ones a hook reports working.
    ///
    /// Agents working outrank playback here. Both can be true at once, and the
    /// peek has room for one kind of thing — but music is ambient and lasts for
    /// hours, while an agent working is the transient state you actually want to
    /// know the end of. Playback is one hover away in the panel; the agent, once
    /// it stops, is gone.
    ///
    /// Agents that are merely open never appear here; the expanded panel lists
    /// them. Mirrors `NotchViewModel.workingAgentCount`, which sized the strip.
    private var workingAgents: [AgentActivity] {
        agents.active.filter(\.isHookReported)
    }
    private var currentLive: LiveActivity? { liveActivities.active.first }

    /// Each side of the notch gets exactly half of what is left over, so the
    /// gap between them sits precisely over the camera housing.
    ///
    /// The strips used to share the free width by layout priority, which let
    /// the trailing one grow towards the middle and shoved the gap off-centre —
    /// the start of a banner line, or the volume rail, then rendered under the
    /// hardware notch where nobody could see it. Content that does not fit a
    /// wing now truncates inside it instead.
    private var wingWidth: CGFloat {
        notch.geometry.peekWingWidth(forPeekWidth: notch.contentSize.width)
    }

    var body: some View {
        HStack(spacing: 0) {
            // A few points clear of the notch on its side, so text that fills
            // a wing does not run right up against the camera housing.
            leading
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .frame(width: wingWidth, alignment: .leading)

            // Reserved for the hardware notch.
            Color.clear.frame(width: notchWidth)

            trailing
                .padding(.leading, 4)
                .padding(.trailing, 10)
                .frame(width: wingWidth, alignment: .trailing)
        }
        // The peek is exactly the notch's height, so centring on the strip is
        // centring on the menu bar.
        .frame(maxHeight: .infinity)
    }

    // MARK: Leading

    /// Driven by `notch.peekContent`, the same decision that sized the strip,
    /// so the two cannot disagree about what the peek is showing.
    @ViewBuilder
    private var leading: some View {
        switch notch.peekContent {
        case .systemHUD:
            if let hud = notch.systemHUD {
                systemHUDIcon(hud)
                    .transition(systemHUDLeadingTransition)
            }
        case .privacy:
            PrivacyActivityMarks(state: privacyActivity.state)
                .accessibilityHidden(true)
                .transition(.scale.combined(with: .opacity))
        case .banner:
            if let banner = notch.banner {
                EventIcon(event: banner, size: 12)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(banner.tint.opacity(0.16))
                    )
                    .transition(.scale.combined(with: .opacity))
            }
        case .focus:
            ZStack {
                ProgressRing(
                    value: focusTimer.snapshot.progress,
                    tint: accent,
                    lineWidth: 2.2
                )
                Image(systemName: "timer")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            .transition(.scale.combined(with: .opacity))
        case .meeting:
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.29, green: 0.62, blue: 0.98))
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
                .transition(.scale.combined(with: .opacity))
        case .live:
            if let activity = currentLive {
                ZStack {
                    Circle().fill(accent.opacity(0.14))
                    if let progress = activity.progress {
                        ProgressRing(value: progress, tint: accent, lineWidth: 2.2)
                            .padding(3)
                    } else {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 22, height: 22)
                .transition(.scale.combined(with: .opacity))
            }
        case .agent:
            // One mark per working agent, in the same order as the names
            // opposite, so the pairing is positional and needs no explaining.
            HStack(spacing: 4) {
                ForEach(workingAgents) { agent in
                    AgentOrb(kind: agent.kind, size: 21, isAnimating: true)
                }
            }
            .transition(.scale.combined(with: .opacity))
        case .media:
            if let track = nowPlaying.nowPlaying {
                ArtworkView(image: track.artwork, cornerRadius: 5, tint: accent)
                    .frame(width: 21, height: 21)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: Trailing

    @ViewBuilder
    private var trailing: some View {
        switch notch.peekContent {
        case .systemHUD:
            if let hud = notch.systemHUD {
                systemHUDMeter(hud)
                    .transition(systemHUDTrailingTransition)
            }
        case .privacy:
            Text(privacyActivity.state.label)
                .font(.system(size: Theme.TextSize.footnote, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel("Privacy indicator")
                .accessibilityValue(privacyActivity.state.accessibilityValue)
                .transition(.opacity)
        case .banner:
            if let banner = notch.banner {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(banner.title)
                        .font(.system(size: Theme.TextSize.body, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if let subtitle = banner.subtitle {
                        Text(subtitle)
                            .font(.system(size: Theme.TextSize.caption))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 136, alignment: .trailing)
                .transition(.opacity)
            }
        case .focus:
            Text(focusTimer.snapshot.timeString)
                .font(.system(size: Theme.TextSize.body, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.primaryText)
                .accessibilityLabel("Focus timer")
                .accessibilityValue(focusTimer.snapshot.timeString + " remaining")
                .transition(.opacity)
        case .meeting:
            if let meeting = meetings.meeting {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(settings.preferences.showMeetingTitlesInPeek
                         ? meeting.title
                         : "Upcoming meeting")
                        .font(.system(size: Theme.TextSize.footnote, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text(meeting.relativeString())
                        .font(.system(size: Theme.TextSize.caption, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: 116, alignment: .trailing)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
        case .live:
            if let activity = currentLive {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(activity.title)
                        .font(.system(size: Theme.TextSize.body, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if let subtitle = activity.subtitle {
                        Text(subtitle)
                            .font(.system(size: Theme.TextSize.caption))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    } else if let progress = activity.progress {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: Theme.TextSize.caption, weight: .medium).monospacedDigit())
                            .foregroundStyle(accent)
                    }
                }
                .frame(maxWidth: 116, alignment: .trailing)
                .transition(.opacity)
            }
        case .agent:
            agentClocks
                .transition(.opacity)
        case .media:
            // Artwork and equaliser only. The title lives one hover away in the
            // expanded panel; putting it here too made the peek a wide slab of
            // text sitting over the menu bar all day.
            if let track = nowPlaying.nowPlaying {
                AudioBars(isAnimating: track.isPlaying, tint: accent)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Hardware controls

    /// Both halves emerge from behind the camera, so the HUD feels like the
    /// hardware surface extending rather than content appearing inside a pill.
    private var systemHUDLeadingTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .move(edge: .trailing).combined(with: .opacity)
    }

    private var systemHUDTrailingTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .move(edge: .leading).combined(with: .opacity)
    }

    private func systemHUDIcon(_ hud: SystemHUDPresentation) -> some View {
        ZStack {
            Image(systemName: systemHUDSymbol(hud))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(systemHUDTint(hud))
                .contentTransition(.symbolEffect(.replace))
                .shadow(color: systemHUDTint(hud).opacity(0.28), radius: 4)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private func systemHUDMeter(_ hud: SystemHUDPresentation) -> some View {
        HStack(spacing: 6) {
            SystemHUDLevelRail(
                value: hud.isMuted ? 0 : hud.clampedLevel,
                tint: systemHUDTint(hud)
            )

            if hud.isMuted {
                Text("MUTED")
                    .font(.system(size: Theme.TextSize.micro, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 36, alignment: .trailing)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(hud.percentage)")
                        .font(.system(size: Theme.TextSize.body, weight: .semibold).monospacedDigit())
                    Text("%")
                        .font(.system(size: Theme.TextSize.micro, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .foregroundStyle(Theme.primaryText)
                .frame(width: 36, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(systemHUDAccessibilityLabel(hud))
        .accessibilityValue(hud.isMuted ? "Muted" : "\(hud.percentage) percent")
    }

    private func systemHUDAccessibilityLabel(_ hud: SystemHUDPresentation) -> String {
        if let detail = hud.detail { return detail }
        switch hud.kind {
        case .volume: return "Volume"
        case .brightness: return "Display brightness"
        case .keyboardBrightness: return "Keyboard brightness"
        case .battery: return "Battery"
        }
    }

    private func systemHUDSymbol(_ hud: SystemHUDPresentation) -> String {
        switch hud.kind {
        case .volume:
            if hud.isMuted || hud.clampedLevel == 0 { return "speaker.slash.fill" }
            if hud.clampedLevel < 0.34 { return "speaker.wave.1.fill" }
            if hud.clampedLevel < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness: return "sun.max.fill"
        case .keyboardBrightness: return "keyboard.fill"
        case .battery:
            return hud.detail == "Charging" ? "bolt.fill" : "battery.100percent"
        }
    }

    private func systemHUDTint(_ hud: SystemHUDPresentation) -> Color {
        switch hud.kind {
        case .battery where hud.clampedLevel < 0.15:
            return Color(red: 0.98, green: 0.35, blue: 0.35)
        case .battery:
            return Color(red: 0.32, green: 0.80, blue: 0.55)
        case .brightness, .keyboardBrightness:
            return Color(red: 0.99, green: 0.72, blue: 0.25)
        case .volume:
            return Theme.primaryText
        }
    }

    /// How long each working agent has been at it.
    ///
    /// The marks opposite already say *who* is working, so naming them again
    /// here only repeated the left half of the strip. The run's length is the
    /// part worth glancing at: it is what tells you whether to go and look.
    /// Status stays one hover away, in the expanded panel.
    ///
    /// One agent gets a clock at the strip's normal text size. Several get
    /// small ones, two to a column and the columns side by side — the strip is
    /// only as tall as the menu bar, which fits two lines, not three. Each
    /// clock is tinted like its mark, so the pairing needs no names.
    ///
    /// The clocks are `Text(_:style: .timer)`, which SwiftUI advances itself:
    /// only the digits redraw each second, not this view, so a long run over
    /// the menu bar costs no more than the orb does.
    private var agentClocks: some View {
        let agents = workingAgents
        let columns = stride(from: 0, to: agents.count, by: 2).map { Array(agents[$0..<min($0 + 2, agents.count)]) }
        return HStack(alignment: .center, spacing: 7) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(column) { agent in
                        AgentClock(agent: agent, compact: agents.count > 1)
                    }
                }
            }
        }
    }
}

/// One agent's elapsed time beside the notch.
private struct AgentClock: View {
    let agent: AgentActivity
    /// Small type, for when several share the strip.
    let compact: Bool

    var body: some View {
        Text(agent.startedAt, style: .timer)
            .foregroundStyle(agent.kind.tint)
            .font(.system(size: compact ? 9.5 : 11.5, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(agent.kind.displayName)
            .accessibilityValue("Working for \(agent.elapsed().clockString)")
    }
}

/// A compact continuous rail with its own value animation. Keeping the fill
/// animation here means rapid hardware-key repeats glide to the next level
/// instead of replacing the whole peek or stepping visibly between samples.
private struct SystemHUDLevelRail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Double
    let tint: Color

    private let horizontalInset: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                    )

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.68), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth(in: contentWidth(proxy.size.width)))
                    .offset(x: horizontalInset)
                    .shadow(color: tint.opacity(0.22), radius: 2.5)

                if value > 0.01 {
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 5, height: 5)
                        .shadow(color: tint.opacity(0.4), radius: 2)
                        .offset(x: thumbOffset(in: proxy.size.width))
                }
            }
        }
        .frame(width: 60, height: 5)
        .animation(
            reduceMotion
                ? .linear(duration: 0.06)
                : .interactiveSpring(response: 0.18, dampingFraction: 0.9),
            value: value
        )
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        guard clamped > 0 else { return 0 }
        return max(width * clamped, 5)
    }

    private func contentWidth(_ width: CGFloat) -> CGFloat {
        max(width - horizontalInset * 2, 0)
    }

    private func thumbOffset(in width: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        let content = contentWidth(width)
        return min(
            max(horizontalInset + content * clamped - 2.5, horizontalInset),
            width - horizontalInset - 5
        )
    }
}
