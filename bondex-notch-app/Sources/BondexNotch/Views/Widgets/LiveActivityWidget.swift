import SwiftUI

struct LiveActivityCard: View {
    @ObservedObject private var service: LiveActivityService
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        self.service = environment.liveActivities
        self.settings = environment.settings
    }

    var body: some View {
        if let activity = service.active.first {
            LiveActivityRow(
                activity: activity,
                accent: settings.effectiveAccentColor,
                trailingText: service.active.count > 1 ? "+\(service.active.count - 1)" : nil
            )
            .notchCard(padding: Theme.compactCardPadding)
        }
    }
}

struct LiveActivityWidget: View {
    @ObservedObject private var service: LiveActivityService
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        self.service = environment.liveActivities
        self.settings = environment.settings
    }

    var body: some View {
        if service.active.isEmpty {
            EmptyStateView(
                systemImage: "waveform.path.ecg",
                title: "No live activities",
                subtitle: "Start one from a script, Shortcut, or terminal."
            )
        } else {
            ScrollingStack(spacing: 6) {
                ForEach(service.active) { activity in
                    LiveActivityRow(
                        activity: activity,
                        accent: settings.effectiveAccentColor
                    )
                    .padding(.vertical, 7)
                    .padding(.horizontal, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.surfaceElevated)
                    )
                }
            }
        }
    }
}

private struct LiveActivityRow: View {
    let activity: LiveActivity
    let accent: Color
    var trailingText: String?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(accent.opacity(0.14))
                if let progress = activity.progress {
                    ProgressRing(value: progress, tint: accent, lineWidth: 2.5)
                        .padding(3)
                } else {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .frame(width: 27, height: 27)

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                if let subtitle = activity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(accent)
            } else if let progress = activity.progress {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(accent)
            }
        }
    }
}
