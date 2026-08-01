import Foundation

/// `--agent-busy <agent> [status]` / `--agent-idle <agent>`.
///
/// The half of the agent indicator that runs *outside* the app: an agent's hook
/// invokes the binary with one of these, and it writes or clears the signal file
/// the running app is watching. It deliberately does nothing else — no launching,
/// no window — so a hook that fires fifty times a turn stays a few milliseconds
/// of process start and one small write.
enum AgentSignalCommand: Equatable {
    case busy(AgentKind, status: String?)
    case idle(AgentKind)

    /// What an argument list turned out to be.
    ///
    /// The three cases exist because "this is not an agent signal" and "this is
    /// an agent signal I could not read" must not be answered the same way.
    /// Returning nil for both meant a misspelled agent name fell through to
    /// `NSApplication.run()` — so a hook wired to an unsupported agent silently
    /// launched *a second copy of the app* on every tool call, each one a
    /// duplicate panel that never exited. A hook is the one caller that repeats
    /// itself dozens of times a turn, which is exactly where a silent
    /// misinterpretation does the most damage.
    enum Parsed: Equatable {
        case command(AgentSignalCommand)
        /// An `--agent-*` flag that could not be turned into a command.
        case invalid(flag: String, message: String)
        /// No agent flag present: the app should start normally.
        case none
    }

    static func parse(_ arguments: [String]) -> Parsed {
        for flag in ["--agent-busy", "--agent-idle"] {
            guard let index = arguments.firstIndex(of: flag) else { continue }

            guard arguments.count > index + 1 else {
                return .invalid(
                    flag: flag,
                    message: "needs an agent name. Expected one of: \(knownAgents)."
                )
            }

            let name = arguments[index + 1]
            // Any plain name is accepted, not just the agents Bondex ships
            // artwork for — an agent it has never heard of still gets to report
            // itself. What is rejected is a name that could not safely *be* a
            // file name, since that is what it becomes.
            guard let kind = AgentKind(name: name) else {
                return .invalid(
                    flag: flag,
                    message: """
                    invalid agent name "\(name)". Use letters, digits, - or _ \
                    (for example: \(knownAgents)).
                    """
                )
            }

            guard flag == "--agent-busy" else { return .command(.idle(kind)) }
            // Everything after the agent name is the status, so a hook can pass
            // a tool name without having to quote it.
            let status = arguments.dropFirst(index + 2)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .command(.busy(kind, status: status.isEmpty ? nil : status))
        }
        return .none
    }

    private static var knownAgents: String {
        AgentKind.known.map(\.id).joined(separator: ", ")
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
