import Foundation

/// Command-line bridge for user-defined activities.
///
/// Examples:
/// `--live-start build --title "Building release" --progress 0.2`
/// `--live-update build --subtitle "Running tests" --progress 0.75`
/// `--live-finish build --message "Build succeeded"`
enum LiveActivityCommand: Equatable {
    case start(id: String, title: String, subtitle: String?, progress: Double?)
    case update(id: String, title: String?, subtitle: String?, progress: Double?)
    case finish(id: String, message: String?)

    enum Parsed: Equatable {
        case command(LiveActivityCommand)
        case invalid(flag: String, message: String)
        case none
    }

    static func parse(_ arguments: [String]) -> Parsed {
        let flags = ["--live-start", "--live-update", "--live-finish"]
        guard let flag = flags.first(where: arguments.contains),
              let index = arguments.firstIndex(of: flag)
        else { return .none }

        guard arguments.count > index + 1 else {
            return .invalid(flag: flag, message: "needs an activity id.")
        }
        let id = arguments[index + 1].lowercased()
        guard LiveActivity.isValidID(id) else {
            return .invalid(
                flag: flag,
                message: "invalid id \"\(id)\". Use 1–48 letters, digits, - or _."
            )
        }

        var title: String?
        var subtitle: String?
        var message: String?
        var progress: Double?
        var cursor = index + 2
        while cursor < arguments.count {
            let option = arguments[cursor]
            guard ["--title", "--subtitle", "--message", "--progress"].contains(option),
                  cursor + 1 < arguments.count
            else {
                return .invalid(flag: flag, message: "unknown or incomplete option \"\(option)\".")
            }
            let value = arguments[cursor + 1]
            switch option {
            case "--title": title = clean(value, limit: 80)
            case "--subtitle": subtitle = clean(value, limit: 120)
            case "--message": message = clean(value, limit: 120)
            case "--progress":
                guard let number = Double(value), (0...1).contains(number) else {
                    return .invalid(flag: flag, message: "--progress must be between 0 and 1.")
                }
                progress = number
            default: break
            }
            cursor += 2
        }

        switch flag {
        case "--live-start":
            guard let title, !title.isEmpty else {
                return .invalid(flag: flag, message: "requires --title.")
            }
            guard message == nil else {
                return .invalid(flag: flag, message: "--message is only valid with --live-finish.")
            }
            return .command(.start(id: id, title: title, subtitle: subtitle, progress: progress))
        case "--live-update":
            guard title != nil || subtitle != nil || progress != nil else {
                return .invalid(flag: flag, message: "needs --title, --subtitle, or --progress.")
            }
            guard message == nil else {
                return .invalid(flag: flag, message: "--message is only valid with --live-finish.")
            }
            return .command(.update(id: id, title: title, subtitle: subtitle, progress: progress))
        default:
            guard title == nil, subtitle == nil, progress == nil else {
                return .invalid(flag: flag, message: "only --message is valid with --live-finish.")
            }
            return .command(.finish(id: id, message: message))
        }
    }

    func run() -> Int32 {
        do {
            switch self {
            case .start(let id, let title, let subtitle, let progress):
                try LiveActivityService.startActivity(
                    id: id, title: title, subtitle: subtitle, progress: progress
                )
            case .update(let id, let title, let subtitle, let progress):
                try LiveActivityService.updateActivity(
                    id: id, title: title, subtitle: subtitle, progress: progress
                )
            case .finish(let id, let message):
                try LiveActivityService.finishActivity(id: id, message: message)
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("bondex: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static func clean(_ value: String, limit: Int) -> String {
        String(
            value.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(limit)
        )
    }
}
