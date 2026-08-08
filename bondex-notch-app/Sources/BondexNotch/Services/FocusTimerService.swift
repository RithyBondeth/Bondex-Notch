import Foundation

struct FocusTimerSnapshot: Equatable {
    enum Phase: Equatable {
        case idle
        case running
        case paused
    }

    var phase: Phase = .idle
    var duration: TimeInterval = 25 * 60
    var remaining: TimeInterval = 25 * 60

    var isActive: Bool { phase != .idle }
    var isRunning: Bool { phase == .running }
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(1 - remaining / duration, 0), 1)
    }

    var timeString: String {
        let seconds = max(Int(remaining.rounded(.up)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// A restart-safe focus countdown. Only the target date is persisted while the
/// timer runs, so sleeping the Mac or restarting the app cannot lengthen a
/// session accidentally.
@MainActor
final class FocusTimerService: ObservableObject {

    static let commandNotification = Notification.Name("com.bondex.notch.focus.command")
    enum CommandKey {
        static let action = "action"
        static let minutes = "minutes"
    }

    @Published private(set) var snapshot = FocusTimerSnapshot()

    private enum Key {
        static let endDate = "com.bondex.notch.focus.endDate"
        static let duration = "com.bondex.notch.focus.duration"
        static let pausedRemaining = "com.bondex.notch.focus.pausedRemaining"
    }

    private let defaults: UserDefaults
    private let events: EventCenter
    private var timer: Timer?
    private var endDate: Date?
    private var commandObserver: NSObjectProtocol?

    init(defaults: UserDefaults, events: EventCenter) {
        self.defaults = defaults
        self.events = events
        restore()
        commandObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.commandNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            onMainActor { self?.handle(command: notification.userInfo) }
        }
    }

    func start(minutes: Int) {
        let duration = TimeInterval(min(max(minutes, 1), 180) * 60)
        endDate = Date().addingTimeInterval(duration)
        snapshot = FocusTimerSnapshot(
            phase: .running,
            duration: duration,
            remaining: duration
        )
        persistRunning()
        startTicking()
    }

    func pause() {
        guard snapshot.phase == .running else { return }
        tick()
        endDate = nil
        snapshot.phase = .paused
        defaults.removeObject(forKey: Key.endDate)
        defaults.set(snapshot.duration, forKey: Key.duration)
        defaults.set(snapshot.remaining, forKey: Key.pausedRemaining)
        stopTicking()
    }

    func resume() {
        guard snapshot.phase == .paused else { return }
        endDate = Date().addingTimeInterval(snapshot.remaining)
        snapshot.phase = .running
        defaults.removeObject(forKey: Key.pausedRemaining)
        persistRunning()
        startTicking()
    }

    func cancel() {
        stopTicking()
        endDate = nil
        snapshot = FocusTimerSnapshot()
        clearPersistence()
    }

    private func startTicking() {
        stopTicking()
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            onMainActor { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard snapshot.phase == .running, let endDate else { return }
        let remaining = max(endDate.timeIntervalSinceNow, 0)
        guard remaining > 0 else {
            complete()
            return
        }
        snapshot.remaining = remaining
    }

    private func complete() {
        stopTicking()
        endDate = nil
        snapshot = FocusTimerSnapshot()
        clearPersistence()
        events.post(NotchEvent(
            kind: .live,
            title: "Focus complete",
            subtitle: "Time for a break"
        ))
    }

    private func handle(command userInfo: [AnyHashable: Any]?) {
        guard let action = userInfo?[CommandKey.action] as? String else { return }
        switch action {
        case "start":
            start(minutes: userInfo?[CommandKey.minutes] as? Int ?? 25)
        case "pause": pause()
        case "resume": resume()
        case "cancel": cancel()
        default: break
        }
    }

    private func restore() {
        let duration = defaults.double(forKey: Key.duration)
        if let endDate = defaults.object(forKey: Key.endDate) as? Date,
           duration > 0, endDate > Date() {
            self.endDate = endDate
            snapshot = FocusTimerSnapshot(
                phase: .running,
                duration: duration,
                remaining: endDate.timeIntervalSinceNow
            )
            startTicking()
        } else {
            let paused = defaults.double(forKey: Key.pausedRemaining)
            if duration > 0, paused > 0 {
                snapshot = FocusTimerSnapshot(
                    phase: .paused,
                    duration: duration,
                    remaining: paused
                )
            } else {
                clearPersistence()
            }
        }
    }

    private func persistRunning() {
        defaults.set(endDate, forKey: Key.endDate)
        defaults.set(snapshot.duration, forKey: Key.duration)
    }

    private func clearPersistence() {
        defaults.removeObject(forKey: Key.endDate)
        defaults.removeObject(forKey: Key.duration)
        defaults.removeObject(forKey: Key.pausedRemaining)
    }
}
