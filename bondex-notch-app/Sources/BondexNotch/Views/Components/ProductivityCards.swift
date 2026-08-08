import SwiftUI

struct FocusTimerCard: View {
    @ObservedObject private var timer: FocusTimerService
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        self.timer = environment.focusTimer
        self.settings = environment.settings
    }

    private var accent: Color { settings.effectiveAccentColor }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ProgressRing(
                    value: timer.snapshot.isActive ? timer.snapshot.progress : 0,
                    tint: accent,
                    lineWidth: 2.5
                )
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(timer.snapshot.isActive ? "Focus session" : "Focus timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(timer.snapshot.isActive
                     ? timer.snapshot.timeString
                     : "\(settings.preferences.defaultFocusMinutes) minutes")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 6)

            if timer.snapshot.isActive {
                NotchButton(
                    systemImage: timer.snapshot.isRunning ? "pause.fill" : "play.fill",
                    size: 10,
                    isProminent: true,
                    tint: accent
                ) {
                    timer.snapshot.isRunning ? timer.pause() : timer.resume()
                }
                .accessibilityLabel(timer.snapshot.isRunning ? "Pause focus timer" : "Resume focus timer")

                NotchButton(systemImage: "xmark", size: 9, tint: Theme.secondaryText) {
                    timer.cancel()
                }
                .accessibilityLabel("Cancel focus timer")
            } else {
                Button("Start") {
                    timer.start(minutes: settings.preferences.defaultFocusMinutes)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.small)
                .accessibilityHint("Starts a focus countdown")
            }
        }
        .notchCard(padding: Theme.compactCardPadding)
        .accessibilityElement(children: .contain)
    }
}

struct UpcomingMeetingCard: View {
    @ObservedObject private var meetings: UpcomingMeetingService

    init(environment: AppEnvironment) {
        self.meetings = environment.meetings
    }

    var body: some View {
        if let meeting = meetings.meeting, meeting.isRelevantToHome() {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.29, green: 0.62, blue: 0.98))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.06), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text(meeting.relativeString())
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer(minLength: 6)

                if meeting.joinURL != nil {
                    Button("Join") { meetings.join(meeting) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityHint("Opens the meeting link")
                }
            }
            .notchCard(padding: Theme.compactCardPadding)
            .accessibilityElement(children: .contain)
        }
    }
}
