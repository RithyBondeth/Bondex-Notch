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

    /// The agent the peek is reporting, if any.
    ///
    /// An agent working outranks playback here. Both can be true at once, and
    /// the peek has room for exactly one thing — but music is ambient and lasts
    /// for hours, while an agent working is the transient state you actually
    /// want to know the end of. Playback is one hover away in the panel; the
    /// agent, once it stops, is gone.
    private var agent: AgentActivity? { agents.active.first }

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
            Image(systemName: banner.kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(banner.kind.tint)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(banner.kind.tint.opacity(0.16))
                )
                .transition(.scale.combined(with: .opacity))
        } else if let agent {
            AgentOrb(kind: agent.kind, size: 21)
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
        } else if let agent {
            agentLabel(agent)
                .transition(.opacity)
        } else if let track = nowPlaying.nowPlaying {
            // Artwork and equaliser only. The title lives one hover away in the
            // expanded panel; putting it here too made the peek a wide slab of
            // text sitting over the menu bar all day.
            AudioBars(isAnimating: track.isPlaying, tint: accent)
                .transition(.opacity)
        }
    }

    /// The agent's name and how long it has been at it.
    ///
    /// The clock is the whole point of the trailing strip: "Claude is working"
    /// is something you already knew, and "for 6:20" is the thing that tells you
    /// whether to go and look. It ticks once a second — not the 15Hz the
    /// expanded player uses — because this sits over the menu bar for the entire
    /// length of a run, and a seconds clock gains nothing from finer steps.
    private func agentLabel(_ agent: AgentActivity) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: 5) {
                // The name and the clock are short, and both are useless
                // abbreviated — so they are fixed and the status absorbs
                // whatever width is left. Left flexible, SwiftUI splits the
                // strip evenly between the three and truncates the only one
                // that had anything to say.
                Text(agent.kind.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize()

                // What it is doing, when the agent bothered to say. This is the
                // part no heuristic could ever have recovered, and it is the
                // reason the signal file carries a payload at all.
                if let status = agent.status {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                        // Middle, not tail: "Editing PeekView.swift" cut at the
                        // tail becomes "Editing…", which drops the only word
                        // that was worth showing.
                        .truncationMode(.middle)
                }

                Text(agent.elapsed(at: timeline.date).clockString)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(agent.kind.tint)
                    .fixedSize()
            }
            .lineLimit(1)
        }
    }
}
