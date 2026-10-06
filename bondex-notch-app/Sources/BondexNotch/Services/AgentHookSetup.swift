import Foundation

/// Writes Bondex's hook into an agent's own settings, and checks that it is
/// still there and complete.
///
/// Setting hooks up by hand meant copying a command into a file that differs
/// per agent, once for each of several events — and it went stale silently.
/// Installs from before "Needs you" have no `PermissionRequest` hook, so the
/// notch never says an agent is waiting; moving the app breaks every hook at
/// once. Both look exactly like "nothing is happening".
///
/// The agent's file is edited, not replaced: every other key and every other
/// hook stays where it was, in the file's own layout, and the original is kept
/// beside it as `<name>.bondex-backup`. A file that cannot be read as plain JSON
/// is left alone and reported, never "repaired".
struct AgentHookSetup {

    /// Where one agent keeps its hooks, and the events Bondex listens to.
    struct Target: Equatable {
        let kind: AgentKind
        let file: URL
        let events: [String]
        /// Seconds, written on each new hook. A hook that hangs holds the agent
        /// up, and Bondex's returns in about 10 ms.
        let timeout: Int?
        /// The agent holds back new or changed hooks until they are reviewed,
        /// so the person should expect that rather than be surprised by it.
        let asksToTrustChanges: Bool

        /// The folder the agent keeps its settings in. Its absence means the
        /// agent is not on this Mac, so there is nothing to set up.
        var agentDirectory: URL { file.deletingLastPathComponent() }

        /// The path the way people write it, for display.
        var displayPath: String {
            let home = NSHomeDirectory()
            let path = file.path
            return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        }

        static func standard(
            for kind: AgentKind,
            home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Target? {
            switch kind.id {
            case AgentKind.claude.id:
                let directory = environment["CLAUDE_CONFIG_DIR"]?
                    .split(separator: ",").first
                    .map { URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces), isDirectory: true) }
                    ?? home.appendingPathComponent(".claude", isDirectory: true)
                return Target(
                    kind: kind,
                    file: directory.appendingPathComponent("settings.json"),
                    // PostToolUse clears "Needs you" the moment an approved
                    // tool finishes, rather than at the next one. StopFailure
                    // ends a turn that died on an API error, which never sends
                    // Stop.
                    events: [
                        "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                        "Notification", "Stop", "StopFailure", "SessionEnd"
                    ],
                    timeout: 2,
                    asksToTrustChanges: false
                )
            case AgentKind.codex.id:
                let directory = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
                    .map { URL(fileURLWithPath: $0, isDirectory: true) }
                    ?? home.appendingPathComponent(".codex", isDirectory: true)
                return Target(
                    kind: kind,
                    file: directory.appendingPathComponent("hooks.json"),
                    // Read off the installed build's own event list. Codex has
                    // no Notification event; its approvals arrive as
                    // PermissionRequest, as Claude Code's do.
                    events: ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"],
                    timeout: 2,
                    // Codex records a hash per hook, and a new or changed one
                    // "needs review before it can run".
                    asksToTrustChanges: true
                )
            default:
                // Gemini's events have other names and other payloads, and its
                // hooks are not yet verified firing, so it is set up by hand.
                return nil
            }
        }
    }

    enum State: Equatable {
        /// The agent's settings folder is not on this Mac.
        case agentMissing
        case notSetUp
        /// Set up, but without some events — typically an install from before
        /// they were added.
        case incomplete(missing: [String])
        /// Every event is wired, but to a different copy of the app.
        case otherCopy(path: String)
        case ready
        /// The file is there but is not JSON Bondex can safely edit.
        case unreadable(String)

        var hasBondexHooks: Bool {
            switch self {
            case .incomplete, .otherCopy, .ready: return true
            case .agentMissing, .notSetUp, .unreadable: return false
            }
        }
    }

    enum Change: Equatable {
        case unchanged
        /// What was written, and where the original went (nil for a file Bondex
        /// created).
        case updated(added: [String], repointed: Int, removed: Int, backup: URL?)
    }

    struct SetupError: Error, LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    let target: Target
    /// The executable the hooks should run: this copy of the app.
    let binaryPath: String

    init(target: Target, binaryPath: String = AgentHookSetup.currentBinaryPath) {
        self.target = target
        self.binaryPath = binaryPath
    }

    static var currentBinaryPath: String {
        Bundle.main.executableURL?.path ?? "/Applications/Bondex Notch.app/Contents/MacOS/BondexNotch"
    }

    /// The one command every event runs. Claude Code and Codex pass the event
    /// as JSON on stdin, which is how one command covers all of them.
    var command: String { "\"\(binaryPath)\" --agent-hook \(target.kind.id)" }

    // MARK: Files

    func state() -> State {
        guard FileManager.default.fileExists(atPath: target.agentDirectory.path) else { return .agentMissing }
        let file = target.file.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: file.path) else { return .notSetUp }
        guard let data = FileManager.default.contents(atPath: file.path) else {
            return .unreadable("the file couldn't be opened")
        }
        do {
            return Self.evaluate(try OrderedJSON.parse(data), target: target, binaryPath: binaryPath)
        } catch {
            return .unreadable(Self.describe(error))
        }
    }

    /// Adds whatever is missing and repoints hooks at this copy of the app.
    @discardableResult
    func install() throws -> Change {
        try edit { root in
            var summary = Summary()
            let updated = try Self.installing(into: root, target: target, binaryPath: binaryPath, summary: &summary)
            return (updated, summary)
        }
    }

    /// Takes out every hook that runs Bondex for this agent, and nothing else.
    @discardableResult
    func remove() throws -> Change {
        try edit { root in
            var summary = Summary()
            let updated = try Self.removing(from: root, kind: target.kind, summary: &summary)
            return (updated, summary)
        }
    }

    struct Summary: Equatable {
        var added: [String] = []
        var repointed = 0
        var removed = 0
    }

    private func edit(_ transform: (OrderedJSON) throws -> (OrderedJSON, Summary)) throws -> Change {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: target.agentDirectory.path) else {
            throw SetupError(message: "\(target.kind.displayName) isn't set up on this Mac.")
        }
        // Through a symlink to the real file: settings kept in a dotfiles
        // repository are linked into place, and an atomic write to the link
        // would replace it with a plain file.
        let file = target.file.resolvingSymlinksInPath()
        let original = fileManager.contents(atPath: file.path)
        // A file that is there but cannot be opened is not an empty one.
        if original == nil, fileManager.fileExists(atPath: file.path) {
            throw SetupError(message: "\(target.displayPath) couldn't be opened, so it was left alone.")
        }

        let root: OrderedJSON
        do {
            root = try original.map(OrderedJSON.parse) ?? .object([])
        } catch {
            throw SetupError(message: "\(target.displayPath) couldn't be read: \(Self.describe(error)).")
        }

        let (updated, summary) = try transform(root)
        guard updated != root else { return .unchanged }

        let style = original.map(OrderedJSON.Style.detect) ?? OrderedJSON.Style()
        var backup: URL?
        let attributes = try? fileManager.attributesOfItem(atPath: file.path)
        if let original {
            let backupURL = file.appendingPathExtension("bondex-backup")
            try original.write(to: backupURL, options: .atomic)
            backup = backupURL
        }
        try updated.serialized(style: style).write(to: file, options: .atomic)
        // An atomic write makes a new file with default permissions; a
        // settings file someone locked down to 0600 should stay that way.
        if let permissions = attributes?[.posixPermissions] {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
        }

        return .updated(
            added: summary.added,
            repointed: summary.repointed,
            removed: summary.removed,
            backup: backup
        )
    }

    private static func describe(_ error: Error) -> String {
        if let parse = error as? OrderedJSON.ParseError {
            return "\(parse.reason.prefix(1).lowercased() + parse.reason.dropFirst()) at byte \(parse.offset)"
        }
        return error.localizedDescription
    }

    // MARK: Reading the hooks

    /// A hook command that runs Bondex, taken apart.
    struct BondexCommand: Equatable {
        /// The executable, unquoted.
        let binary: String
        /// Everything from the `--agent-` flag on, kept verbatim so repointing
        /// a hook changes only its path.
        let arguments: String
        let agent: String

        private static let flags = ["--agent-hook", "--agent-busy", "--agent-idle", "--agent-attention"]

        init?(_ command: String) {
            guard let flagRange = Self.flags
                .compactMap({ command.range(of: " " + $0 + " ") })
                .min(by: { $0.lowerBound < $1.lowerBound })
            else { return nil }

            var binary = command[..<flagRange.lowerBound].trimmingCharacters(in: .whitespaces)
            if binary.count >= 2,
               let first = binary.first, first == "\"" || first == "'",
               binary.last == first {
                binary = String(binary.dropFirst().dropLast())
            } else {
                binary = binary.replacingOccurrences(of: "\\ ", with: " ")
            }
            guard URL(fileURLWithPath: binary).lastPathComponent == "BondexNotch" else { return nil }

            let arguments = String(command[command.index(after: flagRange.lowerBound)...])
            let words = arguments.split(separator: " ", omittingEmptySubsequences: true)
            guard words.count >= 2 else { return nil }

            self.binary = binary
            self.arguments = arguments
            self.agent = words[1].lowercased()
        }

        func runs(_ kind: AgentKind) -> Bool { agent == kind.id }

        func pointing(at binaryPath: String) -> String {
            "\"\(binaryPath)\" \(arguments)"
        }
    }

    /// Every Bondex command for this agent under one event.
    private static func bondexCommands(in event: OrderedJSON?, for kind: AgentKind) -> [BondexCommand] {
        (event?.arrayValue ?? [])
            .flatMap { $0["hooks"]?.arrayValue ?? [] }
            .compactMap { $0["command"]?.stringValue }
            .compactMap(BondexCommand.init)
            .filter { $0.runs(kind) }
    }

    static func evaluate(_ root: OrderedJSON, target: Target, binaryPath: String) -> State {
        guard root.isObject else { return .unreadable("the file isn't a JSON object") }
        guard let hooks = root["hooks"] else { return .notSetUp }
        guard case .object(let events) = hooks else { return .unreadable("\"hooks\" isn't an object") }

        let missing = target.events.filter { bondexCommands(in: hooks[$0], for: target.kind).isEmpty }
        if missing.count == target.events.count {
            // Nothing for the listed events, but a hook elsewhere — say an old
            // explicit-flag install on events no longer listed — still counts
            // as a setup to bring up to date.
            let elsewhere = events.contains { !bondexCommands(in: $0.value, for: target.kind).isEmpty }
            return elsewhere ? .incomplete(missing: missing) : .notSetUp
        }
        if !missing.isEmpty { return .incomplete(missing: missing) }

        let wanted = URL(fileURLWithPath: binaryPath).standardizedFileURL.path
        for event in events {
            for command in bondexCommands(in: event.value, for: target.kind)
            where URL(fileURLWithPath: command.binary).standardizedFileURL.path != wanted {
                return .otherCopy(path: command.binary)
            }
        }
        return .ready
    }

    // MARK: Editing the hooks

    static func installing(
        into root: OrderedJSON,
        target: Target,
        binaryPath: String,
        summary: inout Summary
    ) throws -> OrderedJSON {
        guard root.isObject else { throw SetupError(message: "The file isn't a JSON object.") }
        var hooks = root["hooks"] ?? .object([])
        guard case .object(var events) = hooks else {
            throw SetupError(message: "\"hooks\" isn't an object, so it was left alone.")
        }

        // Repoint first, in place. Order matters to Codex, which keys its trust
        // on each hook's position: appending keeps every existing hook where
        // it was.
        let wanted = URL(fileURLWithPath: binaryPath).standardizedFileURL.path
        for index in events.indices {
            events[index].value = mapHooks(in: events[index].value) { hook in
                guard let text = hook["command"]?.stringValue,
                      let command = BondexCommand(text), command.runs(target.kind),
                      URL(fileURLWithPath: command.binary).standardizedFileURL.path != wanted
                else { return hook }
                var repointed = hook
                repointed.set("command", to: .string(command.pointing(at: binaryPath)))
                summary.repointed += 1
                return repointed
            }
        }
        hooks = .object(events)

        let command = "\"\(binaryPath)\" --agent-hook \(target.kind.id)"
        for event in target.events where bondexCommands(in: hooks[event], for: target.kind).isEmpty {
            var entries: [OrderedJSON]
            switch hooks[event] {
            case nil: entries = []
            case .array(let existing)?: entries = existing
            case _?: throw SetupError(message: "\"\(event)\" isn't a list of hooks, so it was left alone.")
            }
            var hook: [(key: String, value: OrderedJSON)] = [
                ("type", .string("command")),
                ("command", .string(command))
            ]
            if let timeout = target.timeout { hook.append(("timeout", .number(String(timeout)))) }
            entries.append(.object([("hooks", .array([.object(hook)]))]))
            hooks.set(event, to: .array(entries))
            summary.added.append(event)
        }

        var updated = root
        updated.set("hooks", to: hooks)
        return updated
    }

    static func removing(from root: OrderedJSON, kind: AgentKind, summary: inout Summary) throws -> OrderedJSON {
        guard root.isObject else { throw SetupError(message: "The file isn't a JSON object.") }
        guard let hooks = root["hooks"] else { return root }
        guard case .object(let events) = hooks else {
            throw SetupError(message: "\"hooks\" isn't an object, so it was left alone.")
        }

        func isBondex(_ hook: OrderedJSON) -> Bool {
            hook["command"]?.stringValue.flatMap(BondexCommand.init)?.runs(kind) == true
        }

        var kept: [(key: String, value: OrderedJSON)] = []
        for event in events {
            guard case .array(let entries) = event.value else {
                kept.append(event)
                continue
            }
            var keptEntries: [OrderedJSON] = []
            for entry in entries {
                guard case .array(let entryHooks)? = entry["hooks"] else {
                    keptEntries.append(entry)
                    continue
                }
                let remaining = entryHooks.filter { !isBondex($0) }
                summary.removed += entryHooks.count - remaining.count
                // Only a group Bondex emptied goes; one that was empty already
                // was someone else's choice.
                if remaining.isEmpty, !entryHooks.isEmpty { continue }
                var updated = entry
                if remaining.count != entryHooks.count { updated.set("hooks", to: .array(remaining)) }
                keptEntries.append(updated)
            }
            if keptEntries.isEmpty, !entries.isEmpty { continue }
            kept.append((event.key, .array(keptEntries)))
        }

        var updated = root
        if kept.isEmpty, !events.isEmpty {
            updated.remove("hooks")
        } else {
            updated.set("hooks", to: .object(kept))
        }
        return updated
    }

    /// Applies `transform` to every hook object under one event.
    private static func mapHooks(in event: OrderedJSON, _ transform: (OrderedJSON) -> OrderedJSON) -> OrderedJSON {
        guard case .array(let entries) = event else { return event }
        return .array(entries.map { entry in
            guard case .array(let hooks)? = entry["hooks"] else { return entry }
            var updated = entry
            updated.set("hooks", to: .array(hooks.map(transform)))
            return updated
        })
    }
}
