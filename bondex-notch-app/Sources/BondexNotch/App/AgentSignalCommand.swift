import Darwin
import Foundation

/// `--agent-busy <agent> [status]` / `--agent-idle <agent>` /
/// `--agent-attention <agent> [message]` / `--agent-hook <agent>`.
///
/// The half of the agent indicator that runs *outside* the app: an agent's hook
/// invokes the binary with one of these, and it writes or clears the signal file
/// the running app is watching. It deliberately does nothing else — no launching,
/// no window — so a hook that fires fifty times a turn stays a few milliseconds
/// of process start and one small write.
enum AgentSignalCommand: Equatable {
    case busy(AgentKind, status: String?)
    case idle(AgentKind)
    /// The agent has stopped to wait for the user — a permission prompt, a
    /// question, a plan to approve.
    case attention(AgentKind, message: String?)
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
        for flag in ["--agent-busy", "--agent-idle", "--agent-attention", "--agent-hook"] {
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
            if flag == "--agent-idle" { return .command(.idle(kind)) }
            // Everything after the agent name is the status, so a hook can pass
            // a tool name without having to quote it.
            let text = arguments.dropFirst(index + 2)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let status = text.isEmpty ? nil : text
            if flag == "--agent-attention" { return .command(.attention(kind, message: status)) }
            return .command(.busy(kind, status: status))
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
                switch enrichedAction(kind: kind, fallback: status) {
                case .attention(let message):
                    try AgentActivityService.markNeedsAttention(kind, message: message)
                case .busy(let resolved):
                    try AgentActivityService.markBusy(kind, status: resolved)
                case .idle, .ignore:
                    try AgentActivityService.markBusy(kind, status: status)
                }
            case .idle(let kind):
                try AgentActivityService.markIdle(kind)
            case .attention(let kind, let message):
                try AgentActivityService.markNeedsAttention(kind, message: message)
            case .hook(let kind):
                let data = FileHandle.standardInput.readDataToEndOfFile()
                switch AgentHookInput.action(from: data) {
                case .busy(let status):
                    try AgentActivityService.markBusy(kind, status: status)
                case .attention(let message):
                    try AgentActivityService.markNeedsAttention(kind, message: message)
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

    private func enrichedAction(kind: AgentKind, fallback: String?) -> AgentHookAction {
        guard kind.id == AgentKind.codex.id,
              fallback == nil || fallback?.caseInsensitiveCompare("Working") == .orderedSame,
              isatty(STDIN_FILENO) == 0
        else { return .busy(status: fallback) }

        let data = FileHandle.standardInput.readDataToEndOfFile()
        switch AgentHookInput.action(from: data) {
        case .busy(let status): return .busy(status: status ?? fallback)
        case .attention(let message): return .attention(message: message)
        case .idle, .ignore: return .busy(status: fallback)
        }
    }
}

enum AgentHookAction: Equatable {
    case busy(status: String?)
    /// Stopped and waiting for the user, with what it is waiting for.
    case attention(message: String?)
    case idle
    case ignore
}

/// Turns an agent's hook JSON into a short, glanceable activity line.
///
/// Claude Code, Codex and Gemini CLI all send `hook_event_name` on stdin, so
/// one `--agent-hook` command serves every event. Gemini names the same
/// moments differently (`BeforeTool` for `PreToolUse`, `AfterAgent` for
/// `Stop`) and has its own tools; both are mapped here, from the hook and tool
/// references Gemini CLI 0.55 ships. Parsing in Bondex avoids a jq dependency.
/// Unknown tools still get a readable fallback.
enum AgentHookInput {
    static func action(from data: Data) -> AgentHookAction {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["hook_event_name"] as? String
        else { return .ignore }

        switch event {
        case "PreToolUse", "BeforeTool":
            guard let tool = object["tool_name"] as? String else {
                return .busy(status: nil)
            }
            let input = object["tool_input"] as? [String: Any] ?? [:]
            // Tools whose whole purpose is to hand the turn back to the user.
            if let waiting = waitingMessage(tool: tool) { return .attention(message: waiting) }
            return .busy(status: status(tool: tool, input: input))
        case "PostToolUse", "AfterTool":
            guard let tool = object["tool_name"] as? String else {
                return .busy(status: nil)
            }
            let input = object["tool_input"] as? [String: Any] ?? [:]
            return .busy(status: status(tool: tool, input: input))
        case "UserPromptSubmit", "BeforeAgent":
            return .busy(status: "Thinking")
        case "PermissionRequest":
            // Claude Code is showing an approval dialog for this tool.
            guard let tool = object["tool_name"] as? String else {
                return .attention(message: "Needs your approval")
            }
            let input = object["tool_input"] as? [String: Any] ?? [:]
            return .attention(message: "Approve: \(status(tool: tool, input: input))")
        case "Notification":
            return notificationAction(object)
        // StopFailure: the turn ended on an API error, which sends no Stop.
        // AfterAgent is Gemini's end of a turn.
        case "Stop", "StopFailure", "AfterAgent", "SessionEnd":
            return .idle
        default:
            return .ignore
        }
    }

    /// Claude Code's `Notification` hook covers several things, only some of
    /// which mean "come back": a permission prompt or a question does; the
    /// reminder that an idle session is waiting for its next prompt does not —
    /// the turn already ended, and the `Stop` hook said so.
    private static func notificationAction(_ object: [String: Any]) -> AgentHookAction {
        let message = clean(object["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if let type = object["notification_type"] as? String {
            switch type {
            case "permission_prompt", "elicitation_dialog":
                return .attention(message: message ?? "Needs your approval")
            case "ToolPermission":
                // Gemini's own message reads "Tool Shell requires execution";
                // its details say what the tool is about to do.
                return .attention(message: geminiApproval(object["details"] as? [String: Any]))
            default:
                return .ignore
            }
        }
        // Builds that do not label the notification: recognise the prompt by
        // what it says.
        guard let message,
              message.localizedCaseInsensitiveContains("permission")
                || message.localizedCaseInsensitiveContains("approv")
        else { return .ignore }
        return .attention(message: message)
    }

    /// What a Gemini approval prompt is asking for, in the form Claude Code's
    /// prompts take ("Approve: Running swift test").
    private static func geminiApproval(_ details: [String: Any]?) -> String {
        let details = details ?? [:]
        let action: String?
        switch details["type"] as? String {
        case "exec":
            action = clean(details["command"] as? String).flatMap { $0.isEmpty ? nil : "Running \($0)" }
        case "edit":
            action = clean(details["fileName"] as? String).flatMap { $0.isEmpty ? nil : "Editing \($0)" }
        case "mcp":
            let name = clean(details["toolDisplayName"] as? String) ?? clean(details["toolName"] as? String)
            action = name.flatMap { $0.isEmpty ? nil : "Using \($0)" }
        default:
            action = clean(details["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        return action.map { "Approve: \($0)" } ?? "Needs your approval"
    }

    private static func waitingMessage(tool: String) -> String? {
        switch tool {
        case "AskUserQuestion", "ask_user":
            return "Has a question for you"
        case "ExitPlanMode", "exit_plan_mode":
            return "Plan ready for review"
        case let name where name.hasPrefix("request_user_input"):
            return "Waiting for your input"
        default:
            return nil
        }
    }

    private static func status(tool: String, input: [String: Any]) -> String {
        if let description = clean(input["description"] as? String), !description.isEmpty {
            return description
        }

        switch tool {
        case "Bash", "run_shell_command":
            guard let command = clean(input["command"] as? String), !command.isEmpty else {
                return "Running a command"
            }
            return "Running \(command)"
        case "apply_patch":
            return patchStatus(input["command"] as? String) ?? "Editing code"
        // Claude Code's file tools carry the path, which says far more than
        // the tool's name.
        case "Edit", "MultiEdit", "replace":
            return fileStatus("Editing", path: input["file_path"] as? String)
        case "Write", "write_file":
            return fileStatus("Writing", path: input["file_path"] as? String)
        case "Read", "read_file":
            return fileStatus("Reading", path: input["file_path"] as? String)
        case "read_many_files":
            return "Reading files"
        case "Grep", "Glob", "glob", "grep_search", "search_file_content":
            return "Searching the code"
        case "list_directory":
            return "Looking through files"
        case "WebSearch", "google_web_search":
            return "Searching the web"
        case "WebFetch", "web_fetch":
            return "Reading the web"
        case "view_image":
            return fileStatus("Inspecting", path: input["path"] as? String)
        case "Agent", "spawn_agent":
            return "Delegating work"
        case "update_plan", "TodoWrite", "write_todos":
            return "Updating the plan"
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
