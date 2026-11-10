import SwiftUI

/// The Buddy tab: the mascot, today's water and breaks, and the streak.
struct BuddyWidget: View {
    @ObservedObject private var buddy: WellnessBuddyService
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        self.buddy = environment.buddy
        self.settings = environment.settings
    }

    private var accent: Color { settings.effectiveAccentColor }
    private static let water = Color(red: 0.36, green: 0.72, blue: 1.0)
    private static let movement = Color(red: 0.36, green: 0.82, blue: 0.5)

    var body: some View {
        VStack(spacing: Theme.widgetSpacing) {
            HStack(alignment: .top, spacing: Theme.widgetSpacing) {
                mascotCard
                VStack(spacing: Theme.widgetSpacing) {
                    waterCard
                    breaksCard
                }
            }
            // Both columns as tall as the taller one, and no taller: the panel
            // is measured from its content, and an unbounded card filled it.
            .fixedSize(horizontal: false, vertical: true)
            streakRow
        }
        .animation(Motion.content(settings.motion), value: buddy.needsBreak)
    }

    // MARK: Mascot

    private var mascotCard: some View {
        VStack(spacing: 6) {
            BuddyMascot(
                energy: buddy.energy,
                isThirsty: buddy.isThirsty,
                waterTick: buddy.waterTick,
                isInteractive: true
            )
            .frame(width: 84, height: 84)

            VStack(spacing: 2) {
                Text(buddy.mood.title)
                    .font(.system(size: Theme.TextSize.body, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(buddy.message)
                    .font(.system(size: Theme.TextSize.caption, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(energyTint)
                MeterBar(value: buddy.energy, tint: energyTint, height: 3)
                    .animation(Motion.value(settings.motion), value: buddy.energy)
                Text("\(Int((buddy.energy * 100).rounded()))%")
                    .font(.system(size: Theme.TextSize.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 28, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Energy")
            .accessibilityValue("\(Int((buddy.energy * 100).rounded())) percent")

            if buddy.needsBreak {
                NotchTextButton("Remind me later") { buddy.snooze() }
                    .help("Ask again in 15 minutes")
                    .transition(.opacity)
            }
        }
        .frame(width: 168)
        .frame(maxHeight: .infinity, alignment: .top)
        .notchCard(padding: 10)
    }

    private var energyTint: Color {
        switch buddy.mood {
        case .thriving: return Self.movement
        case .content: return Color(red: 0.72, green: 0.84, blue: 0.36)
        case .droopy: return Theme.attention
        case .wilting: return Color(red: 0.98, green: 0.45, blue: 0.35)
        }
    }

    // MARK: Goals

    private var waterCard: some View {
        GoalCard(
            title: "Water",
            systemImage: "drop.fill",
            tint: Self.water,
            count: buddy.today.glasses,
            goal: buddy.goals.water,
            unit: "glasses",
            detail: lastWaterText
        ) {
            NotchButton(systemImage: "minus", size: 8, tint: Theme.secondaryText) {
                buddy.removeWater()
            }
            .disabled(buddy.today.glasses == 0)
            .opacity(buddy.today.glasses == 0 ? 0.4 : 1)
            .accessibilityLabel("Remove a glass of water")

            PillButton(title: "Glass", systemImage: "plus", tint: Self.water, isProminent: true) {
                buddy.logWater()
            }
            .accessibilityLabel("Log a glass of water")
        }
    }

    private var breaksCard: some View {
        GoalCard(
            title: "Breaks",
            systemImage: "figure.walk",
            tint: Self.movement,
            count: buddy.today.breaks,
            goal: buddy.goals.breaks,
            unit: "breaks",
            detail: stretchText
        ) {
            PillButton(
                title: "Stretched",
                systemImage: nil,
                tint: Self.movement,
                isProminent: buddy.needsBreak
            ) {
                buddy.takeBreakNow()
            }
            .help("Log a break taken at your desk. Stepping away for 5 minutes is noticed by itself.")
        }
    }

    private var lastWaterText: String {
        guard let last = buddy.state.lastWaterAt,
              Calendar.current.isDate(last, inSameDayAs: buddy.now) else {
            return "Nothing yet today"
        }
        return "Last glass " + Self.relative(buddy.now.timeIntervalSince(last))
    }

    private var stretchText: String {
        if buddy.isAway { return "Resting" }
        let minutes = Int(buddy.activeStretch / 60)
        return minutes < 1 ? "Just started" : "At your Mac for \(Self.duration(minutes))"
    }

    // MARK: Streak

    private var streakRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(buddy.streak > 0 ? Color(red: 1.0, green: 0.55, blue: 0.25) : Theme.tertiaryText)
            VStack(alignment: .leading, spacing: 1) {
                Text(buddy.streak == 1 ? "1-day streak" : "\(buddy.streak)-day streak")
                    .font(.system(size: Theme.TextSize.footnote, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(nextBadgeText)
                    .font(.system(size: Theme.TextSize.caption))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                ForEach(BuddyBadge.all) { badge in
                    BadgeMark(badge: badge, isEarned: buddy.state.bestStreak >= badge.days, tint: accent)
                }
            }
        }
        .notchCard(padding: Theme.compactCardPadding)
        .accessibilityElement(children: .combine)
    }

    private var nextBadgeText: String {
        guard let next = buddy.state.nextBadge else { return "Every badge earned" }
        let remaining = next.days - buddy.streak
        let days = remaining == 1 ? "1 more day" : "\(remaining) more days"
        return "Meet both goals \(days) for \(next.title)"
    }

    // MARK: Formatting

    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    static func relative(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        return minutes < 1 ? "just now" : duration(minutes) + " ago"
    }
}

/// A daily goal: a count against its target, a row of pips, and its controls.
private struct GoalCard<Actions: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let count: Int
    let goal: Int
    let unit: String
    let detail: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: Theme.TextSize.body, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(count)")
                        .font(.system(size: Theme.TextSize.body, weight: .bold).monospacedDigit())
                        .foregroundStyle(count >= goal ? tint : Theme.primaryText)
                        .contentTransition(.numericText())
                    Text("/\(goal)")
                        .font(.system(size: Theme.TextSize.caption, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.tertiaryText)
                }
                if count >= goal {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(tint)
                }
                Spacer(minLength: 4)
                actions()
            }
            .accessibilityElement(children: .contain)

            Pips(count: count, goal: goal, tint: tint)

            Text(detail)
                .font(.system(size: Theme.TextSize.caption, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
        }
        .notchCard(padding: Theme.compactCardPadding + 1)
        .accessibilityLabel(title)
        .accessibilityValue("\(count) of \(goal) \(unit)")
    }
}

/// One segment per unit of the goal, filled as it is met.
private struct Pips: View {
    let count: Int
    let goal: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(goal, 1), id: \.self) { index in
                Capsule()
                    .fill(index < count ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.white.opacity(0.1)))
                    .frame(height: 4)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.3), value: count)
        .accessibilityHidden(true)
    }
}

private struct BadgeMark: View {
    let badge: BuddyBadge
    let isEarned: Bool
    let tint: Color

    var body: some View {
        Image(systemName: isEarned ? badge.systemImage : "lock.fill")
            .font(.system(size: isEarned ? 9 : 7, weight: .semibold))
            .foregroundStyle(isEarned ? Color.black.opacity(0.8) : Theme.tertiaryText)
            .frame(width: 20, height: 20)
            .background(
                Circle().fill(
                    isEarned
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color(red: 1.0, green: 0.86, blue: 0.45), Color(red: 0.93, green: 0.62, blue: 0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(Color.white.opacity(0.06))
                )
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(isEarned ? 0.3 : 0.06), lineWidth: 0.7))
            .help(isEarned ? "\(badge.title) — a \(badge.days)-day streak" : "\(badge.title): reach a \(badge.days)-day streak")
            .accessibilityLabel(badge.title)
            .accessibilityValue(isEarned ? "Earned" : "Locked")
    }
}
