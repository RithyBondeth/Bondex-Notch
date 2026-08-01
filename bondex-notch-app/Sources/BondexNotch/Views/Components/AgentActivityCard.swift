import SwiftUI

/// What the peek's marks open into: one row per working agent, saying what it is
/// doing and how long it has been at it.
///
/// This is the other half of the peek. The strip beside the notch answers *who*
/// is working, in as little space as that needs; everything it deliberately
/// leaves out lives here, one hover away, where there is room to show it without
/// truncating. It sits at the top of Home — the default tab — so hovering the
/// notch while an agent is running lands on it without a click.
///
/// Absent entirely when no agent is working, rather than showing an empty state:
/// the panel is measured from its content, so a card with nothing in it would
/// make Home permanently taller for a feature most sessions never trigger.
struct AgentActivityCard: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var agents: AgentActivityService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.agents = environment.agents
    }

    /// Beyond this the card stops listing and starts counting.
    ///
    /// The panel is measured from its content, so an unbounded list would push
    /// Home past the height ceiling and get silently cut off at the bottom —
    /// which reads as a padding bug rather than as clipping, and takes the media
    /// row and the gauges with it. Three is chosen because it covers every
    /// plausible session (a couple of agents plus one more) while keeping the
    /// worst case a fixed, known height.
    private static let maximumRows = 3

    private var visible: [AgentActivity] { Array(agents.active.prefix(Self.maximumRows)) }
    private var overflow: Int { max(agents.active.count - Self.maximumRows, 0) }

    var body: some View {
        VStack(spacing: 7) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, agent in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)
                }
                row(agent)
            }

            if overflow > 0 {
                Text("+\(overflow) more working")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .notchCard(padding: Theme.compactCardPadding)
    }

    private func row(_ agent: AgentActivity) -> some View {
        HStack(spacing: 10) {
            // Still animating: the run is live, and this is the same mark the
            // peek was showing a moment ago.
            AgentOrb(kind: agent.kind, size: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(agent.kind.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)

                // What it is doing, when the agent bothered to say. This is the
                // part no heuristic could ever have recovered, and it is the
                // reason the signal file carries a payload at all.
                Text(agent.status ?? "Working")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    // Middle, not tail: "Editing PeekView.swift" cut at the tail
                    // becomes "Editing…", which drops the only word worth
                    // showing.
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            // The clock is why this is worth opening: "Claude is working" is
            // something the peek already told you, and "for 6:20" is what tells
            // you whether to go and look. One tick a second — the panel is only
            // on screen while you are looking at it, and a seconds clock gains
            // nothing from finer steps.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(agent.elapsed(at: timeline.date).clockString)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(agent.kind.tint)
                    .fixedSize()
            }
        }
    }
}
