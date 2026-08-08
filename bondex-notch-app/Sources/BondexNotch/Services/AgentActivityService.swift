import Darwin
import Foundation
import SwiftUI

// MARK: - Model

/// A coding agent, identified by the name its hook signals with.
///
/// Deliberately *open* rather than a fixed enum. Bondex ships marks, tints and
/// setup instructions for the agents it knows, but an agent it has never heard
/// of still gets to report itself — it simply shows up under the generic mark
/// with whatever name the hook passed. A closed list would mean every new agent
/// needed a release before it could light the notch at all.
///
/// The name becomes a *path component* (the signal file is named for it), so it
/// is sanitised at construction rather than trusted: `--agent-busy ../../../foo`
/// must not be able to write outside the signal directory.
struct AgentKind: Hashable, Identifiable, Sendable {

    /// Lowercased, filesystem-safe. Also the signal file's name.
    let id: String

    /// Rejects anything that is not a plain name, rather than sanitising it into
    /// one. Silently stripping characters would map two different agents onto the
    /// same signal file, and quietly turn a typo into a different agent.
    init?(name: String) {
        let lowered = name.lowercased()
        let isPlain = !lowered.isEmpty
            && lowered.count <= 32
            && lowered.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        guard isPlain else { return nil }
        id = lowered
    }

    /// For the built-in list, whose names are known good.
    private init(known id: String) { self.id = id }

    static let claude = AgentKind(known: "claude")
    static let codex = AgentKind(known: "codex")
    static let gemini = AgentKind(known: "gemini")
    static let opencode = AgentKind(known: "opencode")
    static let ollama = AgentKind(known: "ollama")

    /// The agents Bondex ships artwork and setup instructions for. Anything else
    /// still works; it just arrives without either.
    static let known: [AgentKind] = [.claude, .codex, .gemini, .opencode, .ollama]

    var isKnown: Bool { Self.known.contains(self) }

    var displayName: String {
        switch id {
        case Self.claude.id: return "Claude"
        case Self.codex.id: return "Codex"
        case Self.gemini.id: return "Gemini"
        // Lowercase is the project's own styling, not a typo.
        case Self.opencode.id: return "opencode"
        case Self.ollama.id: return "Ollama"
        default: return id.prefix(1).uppercased() + id.dropFirst()
        }
    }

    /// Claude's mark, as pixel art: one string per row, `X` for a filled cell.
    ///
    /// The other marks are curves and are built in `AgentMarks`; this one is a
    /// grid because it *is* a grid — squared-off blocks that a path description
    /// would only make harder to read. Nil for every other agent.
    ///
    /// Used nominatively: these identify the products themselves, which is the
    /// one thing a product's mark is always allowed to do.
    var pixelMark: [String]? {
        guard self == .claude else { return nil }
        return [
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "..XX.XXXXXX.XX..",
            "..XX.XXXXXX.XX..",
            "XXXXXXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXX",
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "...X.X....X.X...",
            "...X.X....X.X..."
        ]
    }

    var tint: Color {
        switch id {
        // Each product's own colour, so the mark reads as itself rather than as
        // a recoloured copy of itself.
        case Self.claude.id: return Color(red: 0.851, green: 0.467, blue: 0.341)
        case Self.codex.id: return Color(red: 0.42, green: 0.45, blue: 0.98)
        case Self.gemini.id: return Color(red: 0.36, green: 0.55, blue: 0.98)
        case Self.opencode.id: return Color(red: 0.94, green: 0.94, blue: 0.96)
        case Self.ollama.id: return Color(red: 0.86, green: 0.86, blue: 0.88)
        // Unknown agents borrow the generic mark, so they borrow its colour too.
        default: return Color(red: 0.86, green: 0.86, blue: 0.88)
        }
    }

    /// Executable name, as it appears on disk, for the "is this installed"
    /// check that decides whether Settings offers setup instructions.
    ///
    /// Case matters: Claude Code's binary is `claude`, while the Claude desktop
    /// app's is `Claude`. Matching case-insensitively would report the desktop
    /// app as a coding agent.
    var executableName: String { id }

    /// Where this agent's hooks are configured, and under which event names.
    ///
    /// Shown in Settings beside the two commands, because knowing *what* to run
    /// is only half of it — every agent puts its hooks somewhere different, and
    /// under a different name for the same two moments. These were read off the
    /// installed builds rather than from memory: Codex and Gemini both borrow
    /// Claude Code's `{matcher, hooks:[{type, command}]}` shape, but Gemini
    /// renames the events themselves.
    var hookConfigHint: String? {
        switch id {
        case Self.claude.id:
            return "~/.claude/settings.json → hooks.PreToolUse / hooks.Stop"
        case Self.codex.id:
            return "~/.codex/hooks.json → hooks.PreToolUse / hooks.Stop"
        case Self.gemini.id:
            return "~/.gemini/settings.json → hooks.BeforeTool / hooks.AfterAgent"
        default:
            return nil
        }
    }
}

/// One agent, and what it is currently doing.
struct AgentActivity: Identifiable, Equatable {
    let kind: AgentKind
    /// When this run of work began, for the elapsed clock in the peek.
    var startedAt: Date
    /// Optional one-line description the agent supplied, e.g. a tool name.
    var status: String?

    var id: String { kind.id }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        max(date.timeIntervalSince(startedAt), 0)
    }
}

// MARK: - Service

/// Reports when a coding agent is open or working, so the notch can show it.
///
/// Hook signals remain the authoritative source for the detailed live state:
/// "Thinking", "Editing", and so on. Desktop hosts do not all forward user hooks,
/// though, so process presence is also shown as a conservative `Open` fallback.
/// Presence never claims that the agent is actively thinking; it only prevents a
/// running Claude or Codex session from disappearing from the UI completely.
///
/// So the mechanism is a file the agent touches, and the setup is one hook. That
/// costs a one-time configuration step and buys an answer that is exactly right,
/// including the part no heuristic could ever recover: *what* the agent is doing.
///
/// CPU is deliberately not used. Agents spend most of a turn waiting on network
/// responses or child tools, so low CPU says nothing useful about whether a turn
/// is in progress.
@MainActor
final class AgentActivityService: ObservableObject {

    /// Agents currently working, most recently started first.
    @Published private(set) var active: [AgentActivity] = []
    /// Agents with a process running right now, for the Settings hints.
    @Published private(set) var installed: Set<AgentKind> = []

    /// How stale a signal file may be before the agent is assumed to have died
    /// without cleaning up.
    ///
    /// Generous, because it is a *backstop*, not the normal path: a `Stop` hook
    /// removes the file the moment a turn ends, so this only matters when an
    /// agent is killed mid-run. Too short and a long single tool call — a test
    /// suite, a build — would blink the indicator out halfway through.
    static let staleAfter: TimeInterval = 90

    /// Where an agent declares itself busy.
    ///
    /// One file per agent, named for it. Its modification date is the heartbeat
    /// and its first line, if any, is a status to show. Removing it means idle.
    nonisolated static var signalDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".bondex-notch/agents", isDirectory: true)
    }

    private let events: EventCenter
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    /// Runs only while something is active, to expire a stale signal. There is
    /// nothing to poll for when no agent is working — the watcher wakes us.
    private var expiryTimer: Timer?
    private var presenceTimer: Timer?
    private var presentAgents: Set<AgentKind> = []
    private var presenceStartedAt: [AgentKind: Date] = [:]
    private var workingStartedAt: [AgentKind: Date] = [:]

    init(events: EventCenter) {
        self.events = events
    }

    var isWorking: Bool { !active.isEmpty }

    // MARK: Lifecycle

    func start() {
        stop()
        // Created eagerly: a directory watcher needs something to watch, and a
        // hook firing before the directory exists would otherwise be the one
        // signal that goes missing.
        try? FileManager.default.createDirectory(
            at: Self.signalDirectory, withIntermediateDirectories: true
        )
        watch()
        refresh()
        refreshPresence()

        // Desktop agents may not emit hooks, so presence is user-visible and
        // needs to react promptly when one launches or quits.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            onMainActor { self?.refreshPresence() }
        }
        RunLoop.main.add(timer, forMode: .common)
        presenceTimer = timer
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
        expiryTimer?.invalidate()
        expiryTimer = nil
        presenceTimer?.invalidate()
        presenceTimer = nil
        presentAgents.removeAll()
        presenceStartedAt.removeAll()
        workingStartedAt.removeAll()
        active = []
    }

    /// Publishes agents without reading the filesystem, so the offscreen preview
    /// tool can render the indicator on a machine where nothing is running.
    func seedForPreview(_ activities: [AgentActivity]) {
        stop()
        active = activities
    }

    // MARK: Signals

    private func watch() {
        descriptor = open(Self.signalDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.agent.error("Could not watch the agent signal directory")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            onMainActor { self?.refresh() }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    private func refresh() {
        let now = Date()
        var fresh: [AgentActivity] = []

        for kind in Self.signalledAgents() {
            guard let signal = Self.readSignal(for: kind),
                  now.timeIntervalSince(signal.date) < Self.staleAfter
            else { continue }

            // The *file's* date is a heartbeat that moves on every tool call, so
            // the run's start is remembered here instead — otherwise the elapsed
            // clock in the peek would reset itself every few seconds.
            let started = workingStartedAt[kind] ?? signal.date
            workingStartedAt[kind] = started
            fresh.append(AgentActivity(kind: kind, startedAt: started, status: signal.status))
        }

        // Anything that was working and is no longer reporting has finished.
        // Keyed off what we were tracking rather than off a fixed list, because
        // the set of agents is only known from the directory.
        let stillWorking = Set(fresh.map(\.kind))
        for kind in Array(workingStartedAt.keys) where !stillWorking.contains(kind) {
            finish(kind)
        }

        // A running desktop/CLI host is the fallback when lifecycle hooks are
        // unavailable. Never overwrite a richer hook-backed activity.
        for kind in presentAgents where !stillWorking.contains(kind) {
            let started = presenceStartedAt[kind] ?? now
            presenceStartedAt[kind] = started
            fresh.append(AgentActivity(kind: kind, startedAt: started, status: "Open"))
        }
        for kind in Array(presenceStartedAt.keys) where !presentAgents.contains(kind) {
            presenceStartedAt.removeValue(forKey: kind)
        }

        // Most recently started first, so the agent you just set going is the one
        // nearest the notch.
        fresh.sort { $0.startedAt > $1.startedAt }
        if fresh != active { active = fresh }
        scheduleExpiry()
    }

    /// Every agent with a signal file present.
    ///
    /// Read from the directory rather than from `AgentKind.known`, which is what
    /// lets an agent Bondex has never heard of report itself. Names that are not
    /// plain (a stray dotfile, anything with a path separator in it) are dropped
    /// by `AgentKind.init(name:)` rather than trusted.
    nonisolated static func signalledAgents(fileManager: FileManager = .default) -> [AgentKind] {
        let names = (try? fileManager.contentsOfDirectory(atPath: signalDirectory.path)) ?? []
        return names.compactMap(AgentKind.init(name:))
    }

    /// A signal that stops being refreshed has to expire on its own: the file has
    /// not changed, so the directory watcher will never fire again for it.
    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard !active.isEmpty else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            onMainActor { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    /// Posts to the feed when a run ends, so work you walked away from leaves a
    /// trace. Feed only — the peek reported it live for the whole run, and a
    /// banner afterwards would announce something you just watched happen.
    private func finish(_ kind: AgentKind) {
        guard let started = workingStartedAt.removeValue(forKey: kind) else { return }
        let elapsed = Date().timeIntervalSince(started)
        // Anything this short is not a piece of work worth a line in the feed.
        guard elapsed >= 20 else { return }
        events.post(NotchEvent(
            kind: .agent,
            title: "\(kind.displayName) finished",
            subtitle: "Worked for \(elapsed.clockString)",
            agent: kind
        ))
    }

    /// Reads one agent's signal file: when it was last touched, and the optional
    /// status line in it.
    nonisolated static func readSignal(
        for kind: AgentKind,
        fileManager: FileManager = .default
    ) -> (date: Date, status: String?)? {
        let url = signalDirectory.appendingPathComponent(kind.id)
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate
        else { return nil }

        let status = (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n").first
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : String($0.prefix(60)) }
        return (date, status)
    }

    // MARK: Writing (the CLI side)

    /// Marks an agent busy. Called by `--agent-busy`, which is what a hook runs.
    nonisolated static func markBusy(_ kind: AgentKind, status: String?) throws {
        try FileManager.default.createDirectory(
            at: signalDirectory, withIntermediateDirectories: true
        )
        let url = signalDirectory.appendingPathComponent(kind.id)
        try (status ?? "").write(to: url, atomically: true, encoding: .utf8)
        // An atomic write replaces the file, so its modification date is now —
        // which is exactly the heartbeat the watcher reads.
    }

    /// Marks an agent idle. Called by `--agent-idle`, from a `Stop` hook.
    nonisolated static func markIdle(_ kind: AgentKind) throws {
        let url = signalDirectory.appendingPathComponent(kind.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: Presence

    private func refreshPresence() {
        let running = Self.runningAgents()
        installed = running
        guard running != presentAgents else { return }
        presentAgents = running
        refresh()
    }

    /// Which agents have a process running, from their executable paths.
    ///
    /// Used for the Settings hint and the conservative `Open` fallback.
    /// `proc_pidpath` resolves every process this user owns — measured at 617 of
    /// 617 on a normal desktop — so this is reliable for presence, while hooks
    /// remain responsible for the richer activity state.
    nonisolated static func runningAgents() -> Set<AgentKind> {
        var found: Set<AgentKind> = []
        for pid in runningPIDs() {
            if let kind = agentKind(of: pid) {
                found.insert(kind)
                if found.count == AgentKind.known.count { break }
            }
        }
        return found
    }

    private nonisolated static func runningPIDs() -> [pid_t] {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }
        // Room to spare: processes can start between sizing the buffer and
        // filling it, and a short buffer silently truncates the list.
        let capacity = Int(count) / MemoryLayout<pid_t>.size + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytes = proc_listpids(
            UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size)
        )
        guard bytes > 0 else { return [] }
        return Array(pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size)).filter { $0 > 0 }
    }

    nonisolated static func agentKind(of pid: pid_t) -> AgentKind? {
        // `PROC_PIDPATHINFO_MAXSIZE` is a C macro (4 * MAXPATHLEN) and macros do
        // not survive the import into Swift, so the size is spelled out.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return agentKind(forExecutablePath: String(cString: buffer))
    }

    /// Split out from the pid lookup so the matching rules can be tested without
    /// an agent having to be running.
    nonisolated static func agentKind(forExecutablePath path: String) -> AgentKind? {
        let name = (path as NSString).lastPathComponent
        return AgentKind.known.first { $0.executableName == name }
    }
}
