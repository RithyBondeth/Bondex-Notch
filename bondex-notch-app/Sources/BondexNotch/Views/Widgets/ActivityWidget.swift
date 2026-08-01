import SwiftUI

/// An event's icon: the agent's own mark when the event is about an agent,
/// otherwise the symbol for its kind.
///
/// Shared by the feed and the peek's banner so the two never disagree — an
/// agent that was showing its mark in the peek keeps it in the row that reports
/// it finished, rather than turning into a generic sparkle on the way.
struct EventIcon: View {
    let event: NotchEvent
    var size: CGFloat

    var body: some View {
        if let agent = event.agent {
            // Marks are wider than they are tall; height is what has to match
            // the surrounding symbols, so the width follows from the aspect.
            PixelMark(kind: agent)
                .frame(
                    width: size * AgentMarks.aspect(for: agent),
                    height: size
                )
        } else {
            Image(systemName: event.kind.systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(event.tint)
        }
    }
}

/// The activity feed.
///
/// Named "Activity" rather than "Notifications" on purpose: it lists what
/// Bondex observed, which is the most macOS permits. Reading other apps'
/// notifications has no public API.
struct ActivityWidget: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var events: EventCenter
    @ObservedObject private var notifications: NotificationService
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        self.environment = environment
        self.events = environment.events
        self.notifications = environment.notifications
        self.settings = environment.settings
    }

    var body: some View {
        VStack(spacing: 8) {
            if events.events.isEmpty {
                EmptyStateView(
                    systemImage: "bell.slash",
                    title: "Nothing yet",
                    subtitle: "Track changes, downloads and power events land here."
                )
            } else {
                feed
            }
        }
    }

    private var feed: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Recent")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                Button("Clear") { events.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }

            ScrollingStack(spacing: 5) {
                ForEach(events.events) { event in
                    row(event)
                }
            }
        }
    }

    private func row(_ event: NotchEvent) -> some View {
        HStack(spacing: 9) {
            EventIcon(event: event, size: 11)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(event.date, style: .time)
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.surfaceElevated)
        )
    }
}
