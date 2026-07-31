import Darwin
import Foundation
import SwiftUI

// MARK: - Model

/// A coding agent Bondex knows how to recognise.
enum AgentKind: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// The agent's own mark, as pixel art: one string per row, `X` for a filled
    /// cell. Nil for agents drawn from an SF Symbol instead.
    ///
    /// Drawn from a grid rather than shipped as an image asset for two reasons.
    /// It scales to any size without a set of `@2x`/`@3x` exports, and it is
    /// tinted by fill rather than by compositing — which matters because the mark
    /// sits on a near-black panel where a baked-in background would show.
    ///
    /// Used nominatively: this identifies Claude Code itself, which is the one
    /// thing a product's mark is always allowed to do.
    var pixelMark: [String]? {
        switch self {
        case .claude:
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
        case .codex:
            return nil
        }
    }

    /// Fallback for agents with no pixel mark.
    var systemImage: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "curlybraces"
        }
    }

    var tint: Color {
        switch self {
        // Claude Code's own terracotta, so the mark reads as itself rather than
        // as a recoloured copy of itself.
        case .claude: return Color(red: 0.851, green: 0.467, blue: 0.341)
        case .codex: return Color(red: 0.45, green: 0.80, blue: 0.75)
        }
    }

    /// Executable name, as it appears on disk.
    ///
    /// Case matters: Claude Code's binary is `claude`, while the Claude desktop
    /// app's is `Claude`. Matching case-insensitively would report the desktop
    /// app as a coding agent.
    var executableName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
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

    var id: String { kind.rawValue }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        max(date.timeIntervalSince(startedAt), 0)
    }
}

// MARK: - Service

/// Reports when a coding agent is working, so the notch can show it.
///
/// **The agent has to say so.** That is not the first design — the obvious one is
/// to find the agent's process and watch its CPU — and it is worth recording why
/// that does not work, because it looks like it should. Measured against three
/// live Claude Code processes and a Codex process on a machine where an agent was
/// actively mid-task, CPU over a two-second window was **0.000–0.001 cores**, and
/// `proc_listchildpids` reported no children. An agent that is "working" is
/// almost always *blocked* — waiting on a streaming API response, or on a tool it
/// has spawned elsewhere. The CPU signal is not weak, it is absent, and a
/// heuristic built on it would have been an indicator that essentially never lit
/// up while looking like a working feature.
///
/// So the mechanism is a file the agent touches, and the setup is one hook. That
/// costs a one-time configuration step and buys an answer that is exactly right,
/// including the part no heuristic could ever recover: *what* the agent is doing.
///
/// Process discovery is still here, but only to answer "is this agent even
/// installed", which is what lets Settings show setup instructions for the agents
/// you actually use and stay quiet about the rest.
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
    private var startedAt: [AgentKind: Date] = [:]

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

        // Presence only changes when an agent is launched or quits, and it drives
        // nothing but a hint in Settings, so it is sampled rarely.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
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
        startedAt.removeAll()
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

        for kind in AgentKind.allCases {
            guard let signal = Self.readSignal(for: kind),
                  now.timeIntervalSince(signal.date) < Self.staleAfter
            else {
                finish(kind)
                continue
            }

            // The *file's* date is a heartbeat that moves on every tool call, so
            // the run's start is remembered here instead — otherwise the elapsed
            // clock in the peek would reset itself every few seconds.
            let started = startedAt[kind] ?? signal.date
            startedAt[kind] = started
            fresh.append(AgentActivity(kind: kind, startedAt: started, status: signal.status))
        }

        fresh.sort { $0.startedAt > $1.startedAt }
        if fresh != active { active = fresh }
        scheduleExpiry()
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
        guard let started = startedAt.removeValue(forKey: kind) else { return }
        let elapsed = Date().timeIntervalSince(started)
        // Anything this short is not a piece of work worth a line in the feed.
        guard elapsed >= 20 else { return }
        events.post(NotchEvent(
            kind: .agent,
            title: "\(kind.displayName) finished",
            subtitle: "Worked for \(elapsed.clockString)"
        ))
    }

    /// Reads one agent's signal file: when it was last touched, and the optional
    /// status line in it.
    nonisolated static func readSignal(
        for kind: AgentKind,
        fileManager: FileManager = .default
    ) -> (date: Date, status: String?)? {
        let url = signalDirectory.appendingPathComponent(kind.rawValue)
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
        let url = signalDirectory.appendingPathComponent(kind.rawValue)
        try (status ?? "").write(to: url, atomically: true, encoding: .utf8)
        // An atomic write replaces the file, so its modification date is now —
        // which is exactly the heartbeat the watcher reads.
    }

    /// Marks an agent idle. Called by `--agent-idle`, from a `Stop` hook.
    nonisolated static func markIdle(_ kind: AgentKind) throws {
        let url = signalDirectory.appendingPathComponent(kind.rawValue)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: Presence

    private func refreshPresence() {
        installed = Self.runningAgents()
    }

    /// Which agents have a process running, from their executable paths.
    ///
    /// Used only to decide whether Settings should offer setup instructions for
    /// an agent. `proc_pidpath` resolves every process this user owns — measured
    /// at 617 of 617 on a normal desktop — so this is reliable for what it is
    /// asked, which is presence and not activity.
    nonisolated static func runningAgents() -> Set<AgentKind> {
        var found: Set<AgentKind> = []
        for pid in runningPIDs() {
            if let kind = agentKind(of: pid) {
                found.insert(kind)
                if found.count == AgentKind.allCases.count { break }
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
        return AgentKind.allCases.first { $0.executableName == name }
    }
}
