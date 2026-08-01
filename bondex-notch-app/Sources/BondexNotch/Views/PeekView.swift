import SwiftUI

/// The compact state: a strip either side of the notch reporting one live thing.
/// Nothing is ever drawn in the middle, where the hardware notch is.
struct PeekView: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var notch: NotchViewModel
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var nowPlaying: NowPlayingService
    @ObservedObject private var agents: AgentActivityService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.notch = environment.notch
        self.settings = environment.settings
        self.nowPlaying = environment.nowPlaying
        self.agents = environment.agents
    }

    private var accent: Color { settings.effectiveAccent.color }
    private var notchWidth: CGFloat { notch.geometry.notchSize.width }

    /// The agents the peek is reporting.
    ///
    /// Agents working outrank playback here. Both can be true at once, and the
    /// peek has room for one kind of thing — but music is ambient and lasts for
    /// hours, while an agent working is the transient state you actually want to
    /// know the end of. Playback is one hover away in the panel; the agent, once
    /// it stops, is gone.
    private var workingAgents: [AgentActivity] { agents.active }

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
        if let banner = notch.banner {
            EventIcon(event: banner, size: 12)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(banner.tint.opacity(0.16))
                )
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
