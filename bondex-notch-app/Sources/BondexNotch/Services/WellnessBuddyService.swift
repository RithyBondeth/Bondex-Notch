import CoreGraphics
import Foundation

/// Keeps the wellness buddy: watches for breaks, logs water, and remembers the
/// days and streaks between launches.
///
/// Breaks are read from how long the keyboard and pointer have been still,
/// which macOS reports to any app without a permission prompt. Nothing about
/// *what* is typed or clicked is ever read — only the time since the last
/// event of any kind.
@MainActor
final class WellnessBuddyService: ObservableObject {

    /// How often the idle time is sampled. A break is minutes long, so this
    /// only needs to be fine enough that one is noticed promptly.
    static let pollInterval: TimeInterval = 30
    static let snoozeLength: TimeInterval = 15 * 60

    @Published private(set) var state: BuddyState
    /// Advanced on every sample, so views that read energy off the clock
    /// redraw as it drains.
    @Published private(set) var now: Date
    /// Mirrors `state.needsBreak`, separately, so the notch can follow it
    /// without redrawing on every sample.
    @Published private(set) var needsBreak = false
    /// Bumped each time a glass is logged, for the buddy's little splash.
    @Published private(set) var waterTick = 0

    var goals = BuddyGoals() {
        didSet {
            guard goals != oldValue else { return }
            refresh()
        }
    }

    private static let defaultsKey = "com.bondex.notch.buddy.state"

    private let defaults: UserDefaults
    private let clock: () -> Date
    private let idleTime: () -> TimeInterval
    private let calendar: Calendar
    private var timer: Timer?

    var isRunning: Bool { timer != nil }

    init(
        defaults: UserDefaults,
        calendar: Calendar = .current,
        clock: @escaping () -> Date = Date.init,
        idleTime: @escaping () -> TimeInterval = WellnessBuddyService.systemIdleTime
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.clock = clock
        self.idleTime = idleTime
        self.state = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(BuddyState.self, from: $0) } ?? BuddyState()
        self.now = clock()
        needsBreak = state.needsBreak(at: now, goals: goals)
    }

    /// Seconds since the last keyboard, pointer or trackpad event in this
    /// login session.
    nonisolated static func systemIdleTime() -> TimeInterval {
        // `~0` is kCGAnyInputEventType, which Swift does not import by name.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    // MARK: Lifecycle

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            onMainActor { self?.sample() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops sampling. What was recorded stays; the gap until the next start
    /// is judged on its length like any other.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Actions

    func logWater() {
        let now = clock()
        state.logWater(at: now, goals: goals, calendar: calendar)
        waterTick += 1
        commit(at: now)
    }

    func removeWater() {
        let now = clock()
        state.removeWater(at: now, goals: goals, calendar: calendar)
        commit(at: now)
    }

    /// "I stretched" — a break taken without stepping away.
    func takeBreakNow() {
        let now = clock()
        state.takeBreakNow(at: now, goals: goals, calendar: calendar)
        commit(at: now)
    }

    func snooze() {
        let now = clock()
        state.snooze(for: Self.snoozeLength, at: now)
        commit(at: now)
    }

    // MARK: Reading

    var energy: Double { state.energy(at: now, goals: goals) }
    var mood: BuddyMood { state.mood(at: now, goals: goals) }
    var today: BuddyDay { state.day(at: now, calendar: calendar) }
    var streak: Int { state.streak(at: now, goals: goals, calendar: calendar) }
    var isThirsty: Bool { state.isThirsty(at: now, goals: goals, calendar: calendar) }
    var activeStretch: TimeInterval { state.activeStretch(at: now) }
    var isAway: Bool { state.activeSince == nil }

    /// One line in the buddy's voice: the most useful thing to do next.
    var message: String {
        if isAway { return "Welcome back — I'm all rested." }
        if needsBreak { return "Let's stretch and look away for a few minutes." }
        if isThirsty { return "I could use a sip of water." }
        let today = self.today
        if today.isComplete(goals) { return "Every goal met today. Lovely work." }
        switch mood {
        case .thriving: return "Feeling fresh — keep going!"
        case .content: return "A break is coming up soon."
        case .droopy, .wilting: return "Getting tired — a short break would help."
        }
    }

    /// One look at the idle time; the timer calls this every `pollInterval`.
    func sample() {
        let now = clock()
        state.observe(idle: idleTime(), at: now, goals: goals, calendar: calendar)
        commit(at: now)
    }

    // MARK: Private

    private func refresh() {
        let now = clock()
        self.now = now
        let needsBreak = state.needsBreak(at: now, goals: goals)
        if needsBreak != self.needsBreak { self.needsBreak = needsBreak }
    }

    private func commit(at now: Date) {
        refresh()
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    // MARK: Preview

    func seedForPreview(_ state: BuddyState) {
        self.state = state
        refresh()
    }
}
