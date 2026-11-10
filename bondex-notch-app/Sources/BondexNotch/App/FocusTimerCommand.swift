import Foundation

/// Terminal/Shortcuts bridge for the built-in focus timer.
///
/// Examples:
/// `BondexNotch --focus-start 25`
/// `BondexNotch --focus-pause`
/// `BondexNotch --focus-resume`
/// `BondexNotch --focus-cancel`
enum FocusTimerCommand: Equatable {
    case start(minutes: Int)
    case pause
    case resume
    case cancel

    enum Parsed: Equatable {
        case command(FocusTimerCommand)
        case invalid(flag: String, message: String)
        case none
    }

    static func parse(_ arguments: [String]) -> Parsed {
        let flags = ["--focus-start", "--focus-pause", "--focus-resume", "--focus-cancel"]
        guard let flag = flags.first(where: arguments.contains) else { return .none }

        switch flag {
        case "--focus-start":
            guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1,
                  let minutes = Int(arguments[index + 1]), (1...180).contains(minutes) else {
                return .invalid(flag: flag, message: "needs minutes between 1 and 180.")
            }
            return .command(.start(minutes: minutes))
        case "--focus-pause": return .command(.pause)
        case "--focus-resume": return .command(.resume)
        default: return .command(.cancel)
        }
    }

    @MainActor
    func run() -> Int32 {
        var userInfo: [AnyHashable: Any] = [:]
        switch self {
        case .start(let minutes):
            userInfo[FocusTimerService.CommandKey.action] = "start"
            userInfo[FocusTimerService.CommandKey.minutes] = minutes
        case .pause:
            userInfo[FocusTimerService.CommandKey.action] = "pause"
        case .resume:
            userInfo[FocusTimerService.CommandKey.action] = "resume"
        case .cancel:
            userInfo[FocusTimerService.CommandKey.action] = "cancel"
        }

        DistributedNotificationCenter.default().postNotificationName(
            FocusTimerService.commandNotification,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        return 0
    }
}
