import Foundation
import XCTest
@testable import BondexNotch

final class BuddyStateTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let goals = BuddyGoals(water: 2, breaks: 1, breakInterval: 50 * 60)
    /// 2026-03-02 09:00 UTC.
    private let morning = Date(timeIntervalSince1970: 1_772_442_000)

    private func minutes(_ value: Double) -> TimeInterval { value * 60 }

    /// Looks every 30 seconds while someone keeps working, as the service's
    /// timer does. One long jump between looks would read as time away.
    private func work(_ state: inout BuddyState, from start: Date, to end: Date) {
        var time = start
        while time <= end {
            state.observe(idle: 0, at: time, goals: goals, calendar: calendar)
            time = time.addingTimeInterval(30)
        }
    }

    func testEnergyDrainsAcrossAnUnbrokenStretch() {
        var state = BuddyState()
        state.observe(idle: 0, at: morning, goals: goals, calendar: calendar)

        XCTAssertEqual(state.energy(at: morning, goals: goals), 1, accuracy: 0.001)
        XCTAssertEqual(state.mood(at: morning, goals: goals), .thriving)

        let due = morning.addingTimeInterval(goals.breakInterval)
        XCTAssertLessThan(state.energy(at: due, goals: goals), 0.45)
        XCTAssertTrue(state.needsBreak(at: due, goals: goals))
        XCTAssertFalse(state.needsBreak(at: due.addingTimeInterval(-1), goals: goals))

        let longAfter = morning.addingTimeInterval(goals.breakInterval * 2)
        XCTAssertEqual(state.energy(at: longAfter, goals: goals), 0, accuracy: 0.001)
        XCTAssertEqual(state.mood(at: longAfter, goals: goals), .wilting)
    }

    func testStretchBeginsWhenInputDidNotWhenItWasNoticed() {
        var state = BuddyState()
        state.observe(idle: 20, at: morning, goals: goals, calendar: calendar)
        XCTAssertEqual(state.activeSince, morning.addingTimeInterval(-20))
    }

    func testSteppingAwayIsABreakThatRestoresEnergyAndCounts() {
        var state = BuddyState()
        let workedAnHour = morning.addingTimeInterval(minutes(60))
        work(&state, from: morning, to: workedAnHour)
        XCTAssertTrue(state.needsBreak(at: workedAnHour, goals: goals))

        // The pointer and keyboard go still; the idle time climbs each look.
        var endedStretch = false
        var time = workedAnHour
        for step in 1...10 {
            time = workedAnHour.addingTimeInterval(Double(step) * 30)
            endedStretch = state.observe(idle: Double(step) * 30, at: time, goals: goals, calendar: calendar)
            if step < 10 { XCTAssertFalse(endedStretch) }
        }

        XCTAssertTrue(endedStretch)
        XCTAssertNil(state.activeSince)
        XCTAssertEqual(state.energy(at: time, goals: goals), 1, accuracy: 0.001)
        XCTAssertEqual(state.day(at: time, calendar: calendar).breaks, 1)
        XCTAssertEqual(state.lastBreakAt, workedAnHour, "The break began at the last input")
    }

    func testAShortPauseIsNotABreak() {
        var state = BuddyState()
        let later = morning.addingTimeInterval(minutes(30))
        work(&state, from: morning, to: later)
        state.observe(idle: minutes(2), at: later.addingTimeInterval(30), goals: goals, calendar: calendar)
        XCTAssertEqual(state.activeSince, morning)
        XCTAssertEqual(state.day(at: later, calendar: calendar).breaks, 0)
    }

    func testAGapBetweenLooksCountsAsTimeAway() {
        // Asleep, or the app was not running: no looks at all, and the input
        // idle time resets the moment someone wakes the Mac.
        var state = BuddyState()
        let beforeLunch = morning.addingTimeInterval(minutes(30))
        work(&state, from: morning, to: beforeLunch)
        let afterLunch = morning.addingTimeInterval(minutes(90))
        XCTAssertTrue(state.observe(idle: 1, at: afterLunch, goals: goals, calendar: calendar))
        XCTAssertEqual(state.day(at: afterLunch, calendar: calendar).breaks, 1)
        XCTAssertEqual(state.lastBreakAt, beforeLunch)

        // Whoever woke it is back, so a fresh stretch starts at once.
        XCTAssertEqual(state.activeSince, afterLunch.addingTimeInterval(-1))
        XCTAssertEqual(state.energy(at: afterLunch, goals: goals), 1, accuracy: 0.001)

        // Ordinary looks after that do not move it.
        state.observe(idle: 0, at: afterLunch.addingTimeInterval(30), goals: goals, calendar: calendar)
        XCTAssertEqual(state.activeSince, afterLunch.addingTimeInterval(-1))
    }

    func testANightAwayEndsTheStretchWithoutCountingAsABreak() {
        // Closing the lid at the end of the day, or the buddy being switched
        // off for an afternoon, is not a break taken; it must not complete a
        // day's goal on its own.
        var state = BuddyState()
        let evening = morning.addingTimeInterval(minutes(30))
        work(&state, from: morning, to: evening)
        let nextMorning = morning.addingTimeInterval(24 * 60 * 60)

        XCTAssertTrue(state.observe(idle: 2, at: nextMorning, goals: goals, calendar: calendar))
        XCTAssertEqual(state.day(at: morning, calendar: calendar).breaks, 0)
        XCTAssertEqual(state.day(at: nextMorning, calendar: calendar).breaks, 0)
        XCTAssertEqual(state.energy(at: nextMorning, goals: goals), 1, accuracy: 0.001)
    }

    func testBreaksCloseTogetherCountOnce() {
        var state = BuddyState()
        state.takeBreakNow(at: morning, goals: goals, calendar: calendar)
        state.takeBreakNow(at: morning.addingTimeInterval(minutes(3)), goals: goals, calendar: calendar)
        XCTAssertEqual(state.day(at: morning, calendar: calendar).breaks, 1)

        let later = morning.addingTimeInterval(BuddyState.minimumGapBetweenBreaks)
        state.takeBreakNow(at: later, goals: goals, calendar: calendar)
        XCTAssertEqual(state.day(at: later, calendar: calendar).breaks, 2)
    }

    func testStretchingAtTheDeskRestartsTheStretchAndClearsASnooze() {
        var state = BuddyState()
        state.observe(idle: 0, at: morning, goals: goals, calendar: calendar)
        let due = morning.addingTimeInterval(minutes(55))
        state.snooze(for: minutes(15), at: due)
        XCTAssertFalse(state.needsBreak(at: due, goals: goals))
        XCTAssertTrue(state.needsBreak(at: due.addingTimeInterval(minutes(15)), goals: goals))

        state.takeBreakNow(at: due, goals: goals, calendar: calendar)
        XCTAssertNil(state.snoozedUntil)
        XCTAssertEqual(state.activeSince, due)
        XCTAssertEqual(state.energy(at: due, goals: goals), 1, accuracy: 0.001)
    }

    func testWaterWindsTheStretchBackButNeverIntoTheFuture() {
        var state = BuddyState()
        state.observe(idle: 0, at: morning, goals: goals, calendar: calendar)
        let later = morning.addingTimeInterval(minutes(40))
        let before = state.energy(at: later, goals: goals)

        state.logWater(at: later, goals: goals, calendar: calendar)
        XCTAssertEqual(state.activeSince, morning.addingTimeInterval(BuddyState.waterCredit))
        XCTAssertGreaterThan(state.energy(at: later, goals: goals), before)
        XCTAssertEqual(state.day(at: later, calendar: calendar).glasses, 1)

        // Three more glasses in a row cannot bank energy beyond "fresh".
        for _ in 0..<3 { state.logWater(at: later, goals: goals, calendar: calendar) }
        XCTAssertEqual(state.activeSince, later)

        state.removeWater(at: later, goals: goals, calendar: calendar)
        XCTAssertEqual(state.day(at: later, calendar: calendar).glasses, 3)
    }

    func testThirstFollowsTheLastGlass() {
        var state = BuddyState()
        XCTAssertFalse(state.isThirsty(at: morning, goals: goals, calendar: calendar), "Away is not thirsty")
        state.observe(idle: 0, at: morning, goals: goals, calendar: calendar)
        XCTAssertTrue(state.isThirsty(at: morning, goals: goals, calendar: calendar))

        state.logWater(at: morning, goals: goals, calendar: calendar)
        XCTAssertFalse(state.isThirsty(at: morning.addingTimeInterval(minutes(30)), goals: goals, calendar: calendar))
        XCTAssertTrue(state.isThirsty(
            at: morning.addingTimeInterval(BuddyState.thirstyAfter), goals: goals, calendar: calendar
        ))

        state.logWater(at: morning, goals: goals, calendar: calendar)
        XCTAssertFalse(state.isThirsty(
            at: morning.addingTimeInterval(BuddyState.thirstyAfter), goals: goals, calendar: calendar
        ), "The day's goal is met")
    }

    func testStreakCountsCompleteDaysAndKeepsTodayInPlay() {
        var state = BuddyState()
        for offset in 1...3 {
            let day = calendar.date(byAdding: .day, value: -offset, to: morning)!
            state.days[BuddyState.dayKey(for: day, calendar: calendar)] = BuddyDay(glasses: 2, breaks: 1)
        }
        // Four days ago was short of water, which is where the streak began.
        let gap = calendar.date(byAdding: .day, value: -4, to: morning)!
        state.days[BuddyState.dayKey(for: gap, calendar: calendar)] = BuddyDay(glasses: 1, breaks: 3)

        XCTAssertEqual(state.streak(at: morning, goals: goals, calendar: calendar), 3)

        state.takeBreakNow(at: morning, goals: goals, calendar: calendar)
        state.logWater(at: morning, goals: goals, calendar: calendar)
        XCTAssertEqual(state.streak(at: morning, goals: goals, calendar: calendar), 3)
        state.logWater(at: morning, goals: goals, calendar: calendar)
        XCTAssertEqual(state.streak(at: morning, goals: goals, calendar: calendar), 4)
        XCTAssertEqual(state.bestStreak, 4)
        XCTAssertEqual(state.earnedBadges.map(\.days), [1, 3])
        XCTAssertEqual(state.nextBadge?.days, 7)

        // A missed day breaks the streak, but not the badges already earned.
        let dayAfterNext = calendar.date(byAdding: .day, value: 2, to: morning)!
        XCTAssertEqual(state.streak(at: dayAfterNext, goals: goals, calendar: calendar), 0)
        XCTAssertEqual(state.earnedBadges.count, 2)
    }

    func testDayKeysSortLikeDays() {
        let early = BuddyState.dayKey(for: morning, calendar: calendar)
        let late = BuddyState.dayKey(for: calendar.date(byAdding: .day, value: 40, to: morning)!, calendar: calendar)
        XCTAssertEqual(early, "2026-03-02")
        XCTAssertLessThan(early, late)
    }
}

@MainActor
final class WellnessBuddyServiceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.bondex.notch.tests.buddy.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStatePersistsAcrossLaunches() {
        let now = Date()
        let first = WellnessBuddyService(defaults: defaults, clock: { now }, idleTime: { 0 })
        first.logWater()
        first.logWater()
        first.takeBreakNow()

        let second = WellnessBuddyService(defaults: defaults, clock: { now }, idleTime: { 0 })
        XCTAssertEqual(second.today.glasses, 2)
        XCTAssertEqual(second.today.breaks, 1)
        XCTAssertEqual(second.waterTick, 0, "The splash is for this session's glasses only")
    }

    func testNeedsBreakFollowsTheClockAndTheSnooze() {
        var now = Date()
        let buddy = WellnessBuddyService(defaults: defaults, clock: { now }, idleTime: { 0 })
        buddy.goals = BuddyGoals(water: 8, breaks: 6, breakInterval: 20 * 60)
        buddy.start()
        defer { buddy.stop() }
        XCTAssertFalse(buddy.needsBreak)

        // Sampled as the timer would: one long jump between samples would be
        // read as time away from the Mac.
        for _ in 0..<42 {
            now = now.addingTimeInterval(30)
            buddy.sample()
        }
        XCTAssertTrue(buddy.needsBreak)

        buddy.snooze()
        XCTAssertFalse(buddy.needsBreak)

        buddy.takeBreakNow()
        XCTAssertFalse(buddy.needsBreak)
        XCTAssertEqual(buddy.energy, 1, accuracy: 0.001)
    }

    func testGoalsChangeIsAppliedAtOnce() {
        let start = Date()
        var now = start
        let buddy = WellnessBuddyService(defaults: defaults, clock: { now }, idleTime: { 0 })
        buddy.start()
        defer { buddy.stop() }
        now = start.addingTimeInterval(30)
        buddy.sample()
        now = start.addingTimeInterval(60)
        buddy.sample()
        XCTAssertFalse(buddy.needsBreak)

        buddy.goals = BuddyGoals(water: 8, breaks: 6, breakInterval: 60)
        XCTAssertTrue(buddy.needsBreak)
    }
}
