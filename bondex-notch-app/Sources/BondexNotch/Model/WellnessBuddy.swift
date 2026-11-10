import Foundation

/// The daily targets the buddy is cared for against.
struct BuddyGoals: Equatable {
    /// Glasses of water a day.
    var water: Int = 8
    /// Breaks away from the Mac a day.
    var breaks: Int = 6
    /// How long an unbroken stretch at the Mac lasts before the buddy asks for
    /// a break.
    var breakInterval: TimeInterval = 50 * 60
}

/// How the buddy is feeling, which is what it looks like.
enum BuddyMood: Equatable, CaseIterable {
    case thriving
    case content
    case droopy
    case wilting

    init(energy: Double) {
        switch energy {
        case 0.7...: self = .thriving
        case 0.45..<0.7: self = .content
        case 0.2..<0.45: self = .droopy
        default: self = .wilting
        }
    }

    var title: String {
        switch self {
        case .thriving: return "Thriving"
        case .content: return "Doing fine"
        case .droopy: return "A little droopy"
        case .wilting: return "Wilting"
        }
    }
}

/// One calendar day of care.
struct BuddyDay: Codable, Equatable {
    var glasses = 0
    var breaks = 0

    func isComplete(_ goals: BuddyGoals) -> Bool {
        glasses >= goals.water && breaks >= goals.breaks
    }
}

/// A streak milestone. Earned once the best streak reaches `days`, and kept
/// after the streak itself breaks.
struct BuddyBadge: Identifiable, Equatable {
    let days: Int
    let title: String
    let systemImage: String

    var id: Int { days }

    static let all: [BuddyBadge] = [
        BuddyBadge(days: 1, title: "First sprout", systemImage: "sparkle"),
        BuddyBadge(days: 3, title: "Seedling", systemImage: "leaf.fill"),
        BuddyBadge(days: 7, title: "Sapling", systemImage: "camera.macro"),
        BuddyBadge(days: 14, title: "In bloom", systemImage: "laurel.leading"),
        BuddyBadge(days: 30, title: "Evergreen", systemImage: "tree.fill"),
        BuddyBadge(days: 100, title: "Ancient oak", systemImage: "crown.fill")
    ]
}

/// Everything the buddy remembers. A value type whose every rule takes `now`,
/// so the whole of its behaviour is testable without waiting for a clock.
///
/// Energy is not stored. It is read off how long the current unbroken stretch
/// at the Mac has lasted, so it can never drift from what actually happened —
/// a relaunch, a sleep or a crash cannot leave the buddy wilted for a break you
/// did take, or perky for one you did not.
struct BuddyState: Codable, Equatable {

    /// How long without any keyboard or pointer input counts as a break.
    static let breakLength: TimeInterval = 5 * 60
    /// The longest time away that still counts as a break towards the day's
    /// goal. Longer is the end of the day, a night's sleep, or the buddy
    /// switched off for a while: it still ends the stretch, but counting it
    /// would let closing the lid complete a day nobody took breaks in.
    static let longestBreak: TimeInterval = 2 * 60 * 60
    /// The least time between two breaks that both count towards the day's
    /// goal, so stepping away twice in a few minutes, or tapping "Stretched"
    /// repeatedly, is one break rather than several.
    static let minimumGapBetweenBreaks: TimeInterval = 10 * 60
    /// How far a glass of water winds the stretch back.
    static let waterCredit: TimeInterval = 10 * 60
    /// How long since the last glass before the buddy looks thirsty.
    static let thirstyAfter: TimeInterval = 90 * 60
    /// Days of history kept: comfortably more than the longest streak a badge
    /// asks for, which is read from the days themselves.
    static let historyDays = 400
    static let maximumGlasses = 40

    /// When the current unbroken stretch at the Mac began, or nil while away.
    var activeSince: Date?
    /// The last time the service looked. A gap since then longer than a break
    /// — the Mac slept, or the app was not running — is treated as one.
    var lastSeenAt: Date?
    var lastWaterAt: Date?
    /// The last break that counted towards a day's goal.
    var lastBreakAt: Date?
    var snoozedUntil: Date?
    var bestStreak = 0
    /// Keyed by `BuddyState.dayKey`.
    var days: [String: BuddyDay] = [:]

    // MARK: Reading

    func activeStretch(at now: Date) -> TimeInterval {
        guard let activeSince else { return 0 }
        return max(now.timeIntervalSince(activeSince), 0)
    }

    /// 1 after a break, falling steadily while you keep working: a little under
    /// a third is left when a break is due, and none at all a while after.
    func energy(at now: Date, goals: BuddyGoals) -> Double {
        let interval = max(goals.breakInterval, 60)
        let drained = activeStretch(at: now) / (interval * 1.4)
        return min(max(1 - drained, 0), 1)
    }

    func mood(at now: Date, goals: BuddyGoals) -> BuddyMood {
        BuddyMood(energy: energy(at: now, goals: goals))
    }

    func needsBreak(at now: Date, goals: BuddyGoals) -> Bool {
        guard activeStretch(at: now) >= goals.breakInterval else { return false }
        if let snoozedUntil, now < snoozedUntil { return false }
        return true
    }

    /// At the Mac, short of today's water, and nothing to drink for a while.
    func isThirsty(at now: Date, goals: BuddyGoals, calendar: Calendar = .current) -> Bool {
        guard activeSince != nil, day(at: now, calendar: calendar).glasses < goals.water else {
            return false
        }
        guard let lastWaterAt else { return true }
        return now.timeIntervalSince(lastWaterAt) >= Self.thirstyAfter
    }

    func day(at date: Date, calendar: Calendar = .current) -> BuddyDay {
        days[Self.dayKey(for: date, calendar: calendar)] ?? BuddyDay()
    }

    /// Consecutive complete days up to today. Today counts once it is
    /// complete; until then it is still in play, so a streak that ran to
    /// yesterday is shown unbroken.
    func streak(at now: Date, goals: BuddyGoals, calendar: Calendar = .current) -> Int {
        var date = calendar.startOfDay(for: now)
        if !day(at: date, calendar: calendar).isComplete(goals) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = yesterday
        }
        var count = 0
        while day(at: date, calendar: calendar).isComplete(goals) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return count
    }

    var earnedBadges: [BuddyBadge] {
        BuddyBadge.all.filter { bestStreak >= $0.days }
    }

    var nextBadge: BuddyBadge? {
        BuddyBadge.all.first { bestStreak < $0.days }
    }

    // MARK: Changing

    /// Folds one look at the input idle time into the state.
    ///
    /// - Parameter idle: seconds since the last keyboard or pointer event.
    /// - Returns: whether this observation ended a stretch with a break.
    @discardableResult
    mutating func observe(
        idle: TimeInterval,
        at now: Date,
        goals: BuddyGoals,
        calendar: Calendar = .current
    ) -> Bool {
        let inputIdle = max(idle, 0)
        // Asleep, or not running: nobody was at this Mac in between, though the
        // input idle time restarted the moment someone woke it.
        var away = inputIdle
        if let lastSeenAt, now.timeIntervalSince(lastSeenAt) >= Self.breakLength {
            away = max(away, now.timeIntervalSince(lastSeenAt))
        }
        lastSeenAt = now

        var endedStretch = false
        if away >= Self.breakLength, activeSince != nil {
            if away <= Self.longestBreak {
                recordBreak(at: now.addingTimeInterval(-away), goals: goals, calendar: calendar)
            } else {
                snoozedUntil = nil
            }
            activeSince = nil
            endedStretch = true
        }
        if inputIdle < Self.breakLength, activeSince == nil {
            activeSince = now.addingTimeInterval(-inputIdle)
        }
        return endedStretch
    }

    /// A break taken without leaving the Mac — a stretch at the desk. Energy is
    /// restored and a new stretch begins now.
    mutating func takeBreakNow(at now: Date, goals: BuddyGoals, calendar: Calendar = .current) {
        recordBreak(at: now, goals: goals, calendar: calendar)
        activeSince = now
        lastSeenAt = now
    }

    mutating func logWater(at now: Date, goals: BuddyGoals, calendar: Calendar = .current) {
        let key = Self.dayKey(for: now, calendar: calendar)
        var today = days[key] ?? BuddyDay()
        guard today.glasses < Self.maximumGlasses else { return }
        today.glasses += 1
        days[key] = today
        lastWaterAt = now
        if let activeSince {
            self.activeSince = min(activeSince.addingTimeInterval(Self.waterCredit), now)
        }
        settle(at: now, goals: goals, calendar: calendar)
    }

    /// Takes back the last glass logged today, for a mis-click.
    mutating func removeWater(at now: Date, goals: BuddyGoals, calendar: Calendar = .current) {
        let key = Self.dayKey(for: now, calendar: calendar)
        guard var today = days[key], today.glasses > 0 else { return }
        today.glasses -= 1
        days[key] = today
    }

    mutating func snooze(for duration: TimeInterval, at now: Date) {
        snoozedUntil = now.addingTimeInterval(duration)
    }

    private mutating func recordBreak(at date: Date, goals: BuddyGoals, calendar: Calendar) {
        snoozedUntil = nil
        if let lastBreakAt, date.timeIntervalSince(lastBreakAt) < Self.minimumGapBetweenBreaks {
            return
        }
        let key = Self.dayKey(for: date, calendar: calendar)
        var day = days[key] ?? BuddyDay()
        day.breaks += 1
        days[key] = day
        lastBreakAt = date
        settle(at: date, goals: goals, calendar: calendar)
    }

    /// Keeps the best streak and the history's size in step after a change.
    private mutating func settle(at now: Date, goals: BuddyGoals, calendar: Calendar) {
        bestStreak = max(bestStreak, streak(at: now, goals: goals, calendar: calendar))
        guard days.count > Self.historyDays,
              let cutoff = calendar.date(byAdding: .day, value: -Self.historyDays, to: now)
        else { return }
        let oldest = Self.dayKey(for: cutoff, calendar: calendar)
        // Keys are zero-padded ISO dates, so they sort as the days do.
        days = days.filter { $0.key >= oldest }
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
