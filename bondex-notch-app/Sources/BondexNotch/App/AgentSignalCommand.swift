import Foundation

/// `--agent-busy <agent> [status]` / `--agent-idle <agent>`.
///
/// The half of the agent indicator that runs *outside* the app: an agent's hook
/// invokes the binary with one of these, and it writes or clears the signal file
/// the running app is watching. It deliberately does nothing else — no launching,
/// no window — so a hook that fires fifty times a turn stays a few milliseconds
/// of process start and one small write.
enum AgentSignalCommand {
    case busy(AgentKind, status: String?)
    case idle(AgentKind)

    static func parse(_ arguments: [String]) -> AgentSignalCommand? {
        func agent(after flag: String) -> (AgentKind, [String])? {
            guard let index = arguments.firstIndex(of: flag),
                  arguments.count > index + 1,
                  let kind = AgentKind(rawValue: arguments[index + 1].lowercased())
            else { return nil }
            return (kind, Array(arguments.dropFirst(index + 2)))
        }

        if let (kind, rest) = agent(after: "--agent-busy") {
            // Everything after the agent name is the status, so a hook can pass
            // a tool name without having to quote it.
            let status = rest.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return .busy(kind, status: status.isEmpty ? nil : status)
        }
        if let (kind, _) = agent(after: "--agent-idle") {
            return .idle(kind)
        }
        return nil
    }

    func run() -> Int32 {
        do {
            switch self {
            case .busy(let kind, let status):
                try AgentActivityService.markBusy(kind, status: status)
            case .idle(let kind):
                try AgentActivityService.markIdle(kind)
            }
            return 0
        } catch {
            // Hooks run on every tool call, and an agent whose hook prints an
            // error on each one is worse than one with no indicator at all.
            // The message goes to stderr; the exit code stays quiet.
            FileHandle.standardError.write(Data("bondex: \(error.localizedDescription)\n".utf8))
            return 0
        }
    }
}
