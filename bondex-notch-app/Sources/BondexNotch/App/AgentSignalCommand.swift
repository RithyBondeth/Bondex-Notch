import Darwin
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
    /// Reads a Codex-compatible hook event from stdin and chooses busy/idle.
    case hook(AgentKind)

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
        for flag in ["--agent-busy", "--agent-idle", "--agent-hook"] {
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

            if flag == "--agent-hook" { return .command(.hook(kind)) }
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
                // Older Bondex setup instructions hardcoded "Working" in the
                // Codex PreToolUse command. Keep those already-trusted hooks
                // useful by enriching that placeholder from the JSON Codex
                // supplies on stdin, without forcing the user to change the
                // command and re-approve its hook trust hash.
                let resolved = enrichedStatus(kind: kind, fallback: status)
                try AgentActivityService.markBusy(kind, status: resolved)
            case .idle(let kind):
                try AgentActivityService.markIdle(kind)
            case .hook(let kind):
                let data = FileHandle.standardInput.readDataToEndOfFile()
                switch AgentHookInput.action(from: data) {
                case .busy(let status):
                    try AgentActivityService.markBusy(kind, status: status)
                case .idle:
                    try AgentActivityService.markIdle(kind)
                case .ignore:
                    break
                }
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

    private func enrichedStatus(kind: AgentKind, fallback: String?) -> String? {
        guard kind.id == AgentKind.codex.id,
              fallback == nil || fallback?.caseInsensitiveCompare("Working") == .orderedSame,
              isatty(STDIN_FILENO) == 0
        else { return fallback }

        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard case .busy(let status) = AgentHookInput.action(from: data) else {
            return fallback
        }
        return status ?? fallback
    }
}

enum AgentHookAction: Equatable {
    case busy(status: String?)
    case idle
    case ignore
}

/// Turns Codex's documented hook JSON into a short, glanceable activity line.
///
/// Parsing it in Bondex avoids a jq dependency and lets the same command work
/// in Codex Desktop and CLI. Unknown tools still get a readable fallback.
enum AgentHookInput {
    static func action(from data: Data) -> AgentHookAction {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["hook_event_name"] as? String
        else { return .ignore }

        switch event {
        case "PreToolUse", "PostToolUse":
            guard let tool = object["tool_name"] as? String else {
                return .busy(status: nil)
            }
            let input = object["tool_input"] as? [String: Any] ?? [:]
            return .busy(status: status(tool: tool, input: input))
        case "UserPromptSubmit":
            return .busy(status: "Thinking")
        case "Stop", "SessionEnd":
            return .idle
        default:
            return .ignore
        }
    }

    private static func status(tool: String, input: [String: Any]) -> String {
        if let description = clean(input["description"] as? String), !description.isEmpty {
            return description
        }

        switch tool {
        case "Bash":
            guard let command = clean(input["command"] as? String), !command.isEmpty else {
                return "Running a command"
            }
            return "Running \(command)"
        case "apply_patch":
            return patchStatus(input["command"] as? String) ?? "Editing code"
        case "view_image":
            return fileStatus("Inspecting", path: input["path"] as? String)
        case "Agent", "spawn_agent":
            return "Delegating work"
        case "update_plan":
            return "Updating the plan"
        case "request_user_input":
            return "Waiting for input"
        default:
            let component = tool.split(separator: "__").last.map(String.init) ?? tool
            return "Using \(humanize(component))"
        }
    }

    private static func patchStatus(_ command: String?) -> String? {
        guard let command else { return nil }
        for (marker, verb) in [
            ("*** Update File: ", "Editing"),
            ("*** Add File: ", "Creating"),
            ("*** Delete File: ", "Removing")
        ] {
            guard let line = command.split(separator: "\n")
                .map(String.init)
                .first(where: { $0.hasPrefix(marker) })
            else { continue }
            return fileStatus(verb, path: String(line.dropFirst(marker.count)))
        }
        return nil
    }

    private static func fileStatus(_ verb: String, path: String?) -> String {
        guard let path = clean(path), !path.isEmpty else { return verb }
        return "\(verb) \(URL(fileURLWithPath: path).lastPathComponent)"
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let firstLine = value.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func humanize(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
    }
}
