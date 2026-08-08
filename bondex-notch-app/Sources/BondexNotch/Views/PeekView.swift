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

    init(environment: AppEnvironment) {
        self.environment = environment
        self.notch = environment.notch
        self.settings = environment.settings
        self.nowPlaying = environment.nowPlaying
        self.agents = environment.agents
        self.liveActivities = environment.liveActivities
        self.focusTimer = environment.focusTimer
        self.meetings = environment.meetings
    }

    private var accent: Color { settings.effectiveAccentColor }
    private var notchWidth: CGFloat { notch.geometry.notchSize.width }

    /// The agents the peek is reporting.
    ///
    /// Agents working outrank playback here. Both can be true at once, and the
    /// peek has room for one kind of thing — but music is ambient and lasts for
    /// hours, while an agent working is the transient state you actually want to
    /// know the end of. Playback is one hover away in the panel; the agent, once
    /// it stops, is gone.
    private var workingAgents: [AgentActivity] { agents.active }
    private var currentLive: LiveActivity? { liveActivities.active.first }

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
                // Both strips ask for infinite width, and without this SwiftUI
                // splits the free space down the middle — handing half the peek
                // to a 21pt piece of artwork and truncating the half that is
                // actually text. The leading strip only ever holds one small
                // mark; the trailing one carries everything with something to
                // say, so it gets first claim on the width.
                .layoutPriority(1)
        }
        // The peek hangs a few points below the menu bar; centre content on the
        // menu bar itself rather than on the panel, or it sits visibly low.
        .padding(.bottom, 6)
        .frame(maxHeight: .infinity)
    }

    // MARK: Leading

    @ViewBuilder
    private var leading: some View {
        if let hud = notch.systemHUD {
            systemHUDIcon(hud)
                .transition(systemHUDLeadingTransition)
        } else if let banner = notch.banner {
            EventIcon(event: banner, size: 12)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(banner.tint.opacity(0.16))
                )
                .transition(.scale.combined(with: .opacity))
        } else if focusTimer.snapshot.isActive {
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
        } else if let meeting = meetings.meeting, meeting.startsSoon() {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.29, green: 0.62, blue: 0.98))
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
                .transition(.scale.combined(with: .opacity))
        } else if let activity = currentLive {
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
        } else if !workingAgents.isEmpty {
            // One mark per working agent, in the same order as the names
            // opposite, so the pairing is positional and needs no explaining.
            HStack(spacing: 4) {
                ForEach(workingAgents) { agent in
                    AgentOrb(kind: agent.kind, size: 21)
                }
            }
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
        if let hud = notch.systemHUD {
            systemHUDMeter(hud)
                .transition(systemHUDTrailingTransition)
        } else if let banner = notch.banner {
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
        } else if focusTimer.snapshot.isActive {
            Text(focusTimer.snapshot.timeString)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.primaryText)
                .accessibilityLabel("Focus timer")
                .accessibilityValue(focusTimer.snapshot.timeString + " remaining")
                .transition(.opacity)
        } else if let meeting = meetings.meeting, meeting.startsSoon() {
            VStack(alignment: .trailing, spacing: 0) {
                Text(settings.preferences.showMeetingTitlesInPeek
                     ? meeting.title
                     : "Upcoming meeting")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(meeting.relativeString())
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: 145, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        } else if let activity = currentLive {
            VStack(alignment: .trailing, spacing: 0) {
                Text(activity.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                if let subtitle = activity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                } else if let progress = activity.progress {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(accent)
                }
            }
            .frame(maxWidth: 145, alignment: .trailing)
            .transition(.opacity)
        } else if !workingAgents.isEmpty {
            agentNames
                .transition(.opacity)
        } else if let track = nowPlaying.nowPlaying {
            // Artwork and equaliser only. The title lives one hover away in the
            // expanded panel; putting it here too made the peek a wide slab of
            // text sitting over the menu bar all day.
            AudioBars(isAnimating: track.isPlaying, tint: accent)
                .transition(.opacity)
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
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 36, alignment: .trailing)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(hud.percentage)")
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    Text("%")
                        .font(.system(size: 8, weight: .bold))
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

    /// Just the names of the agents that are working.
    ///
    /// The status and the elapsed clock used to be here too, and they have moved
    /// into the expanded panel — which is one hover away, and is where there is
    /// actually room for them. Three competing pieces of text in a strip beside
    /// the notch meant the status, the only part carrying new information, was
    /// the one that got truncated. What belongs over the menu bar all day is the
    /// smallest true statement: *who* is working. What they are working on is a
    /// question, and questions deserve a deliberate look rather than a permanent
    /// slab of text.
    ///
    /// Dropping the clock also takes the peek's last `TimelineView` with it, so
    /// the strip no longer re-renders once a second for the entire length of a
    /// run — which, for a panel that sits over the menu bar for tens of minutes,
    /// is the same argument that put the orb on Core Animation.
    private var agentNames: some View {
        HStack(spacing: 5) {
            ForEach(Array(workingAgents.enumerated()), id: \.element.id) { index, agent in
                if index > 0 {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                }
                // Tinted to match its own mark opposite. With one agent this is
                // decoration; with two it is what tells you which name belongs
                // to which mark without counting positions.
                Text(agent.kind.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(agent.kind.tint)
                    .fixedSize()
            }
        }
        .lineLimit(1)
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
        .frame(width: 74, height: 5)
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
