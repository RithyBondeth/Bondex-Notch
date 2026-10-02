import Darwin
import Foundation

/// Where each agent keeps the files the Agents tab reads.
struct AgentUsageRoots: Equatable {
    var claude: [URL]
    var codex: [URL]
    var claudeAppHistory: URL
    /// Claude Code's cached account profile, for the plan name.
    var claudeProfile: URL?

    /// The default locations, honouring the same environment overrides the
    /// agents themselves do. An app launched from Finder rarely inherits them,
    /// so the standard folders are always included as well.
    static func standard(
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AgentUsageRoots {
        let claudeConfigs = (environment["CLAUDE_CONFIG_DIR"] ?? "")
            .split(separator: ",")
            .map { URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces), isDirectory: true) }
        var claude = claudeConfigs.map { $0.appendingPathComponent("projects", isDirectory: true) }
        claude += [
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent(".config/claude/projects", isDirectory: true)
        ]

        var codexHomes = [home.appendingPathComponent(".codex", isDirectory: true)]
        if let custom = environment["CODEX_HOME"], !custom.isEmpty {
            codexHomes.insert(URL(fileURLWithPath: custom, isDirectory: true), at: 0)
        }
        let codex = codexHomes.flatMap {
            [
                $0.appendingPathComponent("sessions", isDirectory: true),
                $0.appendingPathComponent("archived_sessions", isDirectory: true)
            ]
        }

        return AgentUsageRoots(
            claude: unique(claude),
            codex: unique(codex),
            claudeAppHistory: ClaudeAppLimitsReader.historyURL(home: home),
            claudeProfile: claudeConfigs.first.map { $0.appendingPathComponent(".claude.json") }
                ?? home.appendingPathComponent(".claude.json")
        )
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }
    }
}

// MARK: - Ledger

/// Everything read so far, and where each file was left off.
///
/// Confined to the scanner's serial queue. Usage is kept as 15-minute slots
/// rather than per request, each split by agent, project and model: thirty days
/// of heavy use is a few thousand entries, and quarter hours line up with every
/// local midnight on Earth, including the half- and three-quarter-hour time
/// zones, so a day's total is never smeared across two days.
final class AgentUsageLedger {

    static let slotLength: TimeInterval = 15 * 60
    /// Long enough for the 30-day view, plus a day of slack for time zones.
    static let horizon: TimeInterval = 31 * 86_400
    /// How many sessions the snapshot carries for the activity card.
    static let sessionLimit = 8

    /// What one slot's usage is split by.
    struct Key: Hashable {
        let provider: UsageProvider
        /// Empty when the log did not name one.
        let project: String
        let model: String
    }

    private struct Cursor {
        var offset: UInt64 = 0
        var codex = CodexFileState()
    }

    private(set) var slots: [Int: [Key: UsageTally]] = [:]
    private(set) var hasLogs: Set<UsageProvider> = []
    private(set) var codexLimits: ProviderLimits?
    private(set) var codexPlan: String?

    private var sessions: [String: AgentSession] = [:]
    private var cursors: [String: Cursor] = [:]
    /// Claude request keys already counted, with the slot they landed in so the
    /// set can be trimmed along with the usage it guards.
    private var seenClaude: [String: Int] = [:]

    static func slot(for date: Date) -> Int {
        Int((date.timeIntervalSince1970 / slotLength).rounded(.down))
    }

    // MARK: Scanning

    func scan(_ roots: AgentUsageRoots, now: Date, fileManager: FileManager = .default) {
        let cutoff = now.addingTimeInterval(-Self.horizon)
        var present = Set<String>()

        for (provider, directories) in [(UsageProvider.claude, roots.claude), (.codex, roots.codex)] {
            for file in Self.logFiles(in: directories, modifiedAfter: cutoff, fileManager: fileManager) {
                hasLogs.insert(provider)
                present.insert(file.path)
                read(file, provider: provider, now: now)
            }
        }

        // A file that rotated out of the horizon, or was deleted, keeps
        // nothing worth remembering about where it was read up to.
        cursors = cursors.filter { present.contains($0.key) }
        prune(before: cutoff)
    }

    /// Feeds one file's new lines in, from where the last scan stopped.
    ///
    /// Only complete lines are consumed: an agent may be halfway through
    /// writing the last one, and it is read whole on the next pass instead.
    private func read(_ file: URL, provider: UsageProvider, now: Date) {
        let path = file.path
        var cursor = cursors[path] ?? Cursor()
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64($0) } ?? 0
        if size < cursor.offset {
            // Rewritten or truncated: start over rather than read from the
            // middle of a line.
            cursor = Cursor()
        }
        guard size > cursor.offset, let handle = try? FileHandle(forReadingFrom: file) else {
            cursors[path] = cursor
            return
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: cursor.offset)
            var carry = Data()
            var consumed = cursor.offset
            let markers = provider == .claude ? [ClaudeLogParser.marker] : CodexLogParser.markers

            while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                carry.append(chunk)
                let used = Self.forEachLine(in: carry, containingAny: markers) { line in
                    ingest(line, provider: provider, file: path, cursor: &cursor, now: now)
                }
                consumed += UInt64(used)
                carry.removeSubrange(0..<used)
            }
            cursor.offset = consumed
        } catch {
            Log.agent.error("Could not read agent log: \(error.localizedDescription)")
        }
        cursors[path] = cursor
    }

    private func ingest(_ line: Data, provider: UsageProvider, file: String, cursor: inout Cursor, now: Date) {
        switch provider {
        case .claude:
            guard let record = ClaudeLogParser.record(from: line) else { return }
            if let key = record.key {
                guard seenClaude[key] == nil else { return }
                seenClaude[key] = Self.slot(for: record.date)
            }
            // Subagents log to their own files under the parent's session ID,
            // so keying on it keeps one session one row.
            let session = "claude:" + (record.session ?? file)
            // A session belongs to the folder it was started in. Claude Code
            // logs the *current* directory on every line, which follows each
            // `cd` into a subfolder and would split one project into several.
            let project = sessions[session]?.project ?? record.project
            add(
                record.tally,
                key: Key(provider: .claude, project: project ?? "", model: record.model),
                session: session,
                at: record.date,
                now: now
            )

        case .codex:
            for event in CodexLogParser.events(from: line, state: &cursor.codex, now: now) {
                switch event {
                case let .usage(date, model, project, tokens):
                    var tally = UsageTally(tokens: tokens)
                    if let model, let cost = AgentPricing.cost(model: model, tokens: tokens) {
                        tally.cost = cost
                    } else {
                        tally.unpricedTokens = tokens.total
                    }
                    add(
                        tally,
                        key: Key(provider: .codex, project: project ?? "", model: model ?? ""),
                        session: "codex:" + file,
                        at: date,
                        now: now
                    )
                case let .limits(limits, plan):
                    // Files are read in no particular order, and a resumed
                    // session appends to an old one, so the newest reading wins
                    // by its own date rather than by arrival.
                    if limits.observedAt >= (codexLimits?.observedAt ?? .distantPast) {
                        codexLimits = limits
                        if let plan { codexPlan = plan }
                    }
                }
            }
        }
    }

    private func add(_ tally: UsageTally, key: Key, session: String, at date: Date, now: Date) {
        // Clock skew happens; the far future does not.
        guard date > now.addingTimeInterval(-Self.horizon), date < now.addingTimeInterval(86_400) else { return }
        slots[Self.slot(for: date), default: [:]][key, default: UsageTally()] += tally

        var entry = sessions[session] ?? AgentSession(id: session, provider: key.provider, lastActivity: date)
        // The project is fixed by the session's first line; the model is the
        // newest one, since a session can switch models partway. Lines arrive
        // in order within a file but files in no order, so only a newer
        // request may change it.
        if entry.project == nil, !key.project.isEmpty { entry.project = key.project }
        if date >= entry.lastActivity {
            entry.lastActivity = date
            if !key.model.isEmpty { entry.model = key.model }
        } else if entry.model == nil, !key.model.isEmpty {
            entry.model = key.model
        }
        sessions[session] = entry
    }

    private func prune(before cutoff: Date) {
        let oldest = Self.slot(for: cutoff)
        slots = slots.filter { $0.key >= oldest }
        sessions = sessions.filter { $0.value.lastActivity >= cutoff }
        // Keys are kept a day longer than usage, so a resumed session copying
        // a just-expired request forward cannot count it again.
        let keyCutoff = oldest - Int(86_400 / Self.slotLength)
        seenClaude = seenClaude.filter { $0.value >= keyCutoff }
    }

    /// Calls `body` for each complete line that contains one of `markers`, and
    /// returns how many bytes of complete lines there were.
    ///
    /// The marker test runs on raw bytes with `memmem`, before any JSON is
    /// decoded or any line is copied, which is what keeps a first scan of a
    /// month of logs affordable: the lines that carry usage are a small share
    /// of the bytes.
    static func forEachLine(in data: Data, containingAny markers: [[UInt8]], _ body: (Data) -> Void) -> Int {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            var start = 0
            while start < buffer.count,
                  let newline = memchr(base + start, 0x0A, buffer.count - start) {
                let end = base.distance(to: newline)
                let length = end - start
                if length > 0, markers.contains(where: { marker in
                    marker.withUnsafeBytes { memmem(base + start, length, $0.baseAddress, $0.count) != nil }
                }) {
                    body(Data(bytes: base + start, count: length))
                }
                start = end + 1
            }
            return start
        }
    }

    static func logFiles(in directories: [URL], modifiedAfter cutoff: Date, fileManager: FileManager) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        var files: [URL] = []
        for directory in directories {
            guard let enumerator = fileManager.enumerator(
                at: directory.resolvingSymlinksInPath(),
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      (values.contentModificationDate ?? .distantPast) >= cutoff
                else { continue }
                files.append(url)
            }
        }
        return files
    }

    // MARK: Summaries

    func snapshot(
        now: Date,
        claudeLimits: ProviderLimits?,
        claudePlan: String? = nil,
        calendar: Calendar = .current
    ) -> AgentUsageSnapshot {
        let recent = sessions.values.sorted { $0.lastActivity > $1.lastActivity }
        var snapshot = AgentUsageSnapshot(
            sessions: Array(recent.prefix(Self.sessionLimit)),
            scannedAt: now
        )
        for provider in UsageProvider.allCases {
            let newest = recent.first { $0.provider == provider }
            snapshot.providers[provider] = ProviderStatus(
                limits: provider == .claude ? claudeLimits : codexLimits,
                plan: provider == .claude ? claudePlan : codexPlan,
                model: newest?.model,
                lastActivity: newest?.lastActivity,
                hasLogs: hasLogs.contains(provider)
            )
        }
        for range in UsageRange.allCases {
            snapshot.summaries[range] = summary(range, now: now, calendar: calendar)
        }
        return snapshot
    }

    private func summary(_ range: UsageRange, now: Date, calendar: Calendar) -> UsageRangeSummary {
        let today = calendar.startOfDay(for: now)
        var bounds: [Date] = []
        if range.barsAreHourly {
            // Iterated by the calendar rather than in 3,600 s steps, so a day
            // that gains or loses an hour to daylight saving still ends at its
            // own midnight.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
            var hour = today
            while hour < tomorrow {
                bounds.append(hour)
                hour = calendar.date(byAdding: .hour, value: 1, to: hour) ?? tomorrow
            }
            bounds.append(tomorrow)
        } else {
            for offset in stride(from: -(range.barCount - 1), through: 1, by: 1) {
                bounds.append(calendar.date(byAdding: .day, value: offset, to: today) ?? today)
            }
        }

        var summary = UsageRangeSummary(range: range)
        var projects: [String: [UsageProvider: UsageTally]] = [:]
        var models: [String: [UsageProvider: UsageTally]] = [:]

        for index in 0..<(bounds.count - 1) {
            var bar = UsageTrendBar(start: bounds[index])
            for slot in Self.slot(for: bounds[index])..<Self.slot(for: bounds[index + 1]) {
                guard let entries = slots[slot] else { continue }
                for (key, tally) in entries {
                    bar.tokens[key.provider, default: 0] += tally.tokens.total
                    bar.cost[key.provider, default: 0] += tally.cost
                    summary.byProvider[key.provider, default: UsageTally()] += tally
                    let project = key.project.isEmpty ? "Other" : key.project
                    projects[project, default: [:]][key.provider, default: UsageTally()] += tally
                    let model = key.model.isEmpty ? "Unknown model" : AgentModelName.display(key.model)
                    models[model, default: [:]][key.provider, default: UsageTally()] += tally
                }
            }
            summary.trend.append(bar)
        }
        summary.byProject = Self.ranked(projects)
        summary.byModel = Self.ranked(models)
        return summary
    }

    /// Highest spend first; tokens break ties, which matters when nothing in
    /// the range could be priced.
    private static func ranked(_ groups: [String: [UsageProvider: UsageTally]]) -> [UsageBreakdownItem] {
        groups.map { name, byProvider in
            let lead = byProvider.max { $0.value.tokens.total < $1.value.tokens.total }?.key ?? .claude
            return UsageBreakdownItem(
                name: name,
                provider: lead,
                tally: byProvider.values.reduce(UsageTally(), +)
            )
        }
        .sorted {
            ($0.tally.cost, $0.tally.tokens.total, $1.name) > ($1.tally.cost, $1.tally.tokens.total, $0.name)
        }
    }
}

// MARK: - Scanner

/// Runs the ledger on a background queue, one scan at a time.
final class AgentUsageScanner: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.bondex.notch.agent-usage", qos: .utility)
    private var ledger = AgentUsageLedger()
    private let roots: AgentUsageRoots
    /// `~/.claude.json` can run to megabytes of project history, so it is
    /// only reread when it changes.
    private var profileModified: Date?
    private var claudePlan: String?

    init(roots: AgentUsageRoots) {
        self.roots = roots
    }

    func scan(now: Date = Date(), completion: @escaping @Sendable (AgentUsageSnapshot) -> Void) {
        queue.async { [self] in
            ledger.scan(roots, now: now)
            let claudeLimits = (try? Data(contentsOf: roots.claudeAppHistory))
                .flatMap(ClaudeAppLimitsReader.samples(from:))
                .flatMap { ClaudeAppLimitsReader.limits(from: $0, now: now) }
            refreshClaudePlan()
            completion(ledger.snapshot(now: now, claudeLimits: claudeLimits, claudePlan: claudePlan))
        }
    }

    private func refreshClaudePlan() {
        guard let url = roots.claudeProfile else { return }
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard modified != profileModified else { return }
        profileModified = modified
        claudePlan = (try? Data(contentsOf: url, options: .mappedIfSafe)).flatMap(ClaudePlanReader.plan(from:))
    }

    /// Drops everything read, so a stopped feature holds no usage in memory.
    func reset() {
        queue.async { [self] in
            ledger = AgentUsageLedger()
            profileModified = nil
            claudePlan = nil
        }
    }

    /// Runs one scan synchronously, for the `--agent-usage-report` check.
    func scanNow(now: Date = Date()) -> AgentUsageSnapshot {
        let result = UnsafeMutableTransferBox<AgentUsageSnapshot?>(nil)
        let done = DispatchSemaphore(value: 0)
        scan(now: now) { snapshot in
            result.value = snapshot
            done.signal()
        }
        done.wait()
        return result.value ?? .empty
    }
}

private final class UnsafeMutableTransferBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

// MARK: - Service

/// Reports how much Claude Code and Codex have been used on this Mac: plan
/// allowances, API-equivalent spend, recent sessions and a trend.
///
/// Everything comes from files the agents already write locally. Bondex signs
/// in to nothing, reads no credentials, and sends nothing anywhere — the
/// numbers are only as fresh as those files, which is why each card says when
/// its reading was taken once it is no longer current.
///
/// Logs are read incrementally: the first scan covers the last 31 days, and
/// every later one reads only the bytes appended since. A scan runs every
/// minute while the tab is enabled, on a utility-priority queue.
@MainActor
final class AgentUsageService: ObservableObject {

    @Published private(set) var snapshot: AgentUsageSnapshot = .empty
    @Published private(set) var isScanning = false

    static let interval: TimeInterval = 60

    private let scanner: AgentUsageScanner
    private var timer: Timer?
    private var isRunning = false
    private var isPreview = false
    /// Bumped on stop, so a scan that finishes afterwards cannot publish.
    private var generation = 0

    init(roots: AgentUsageRoots = .standard()) {
        scanner = AgentUsageScanner(roots: roots)
    }

    func start() {
        guard !isRunning, !isPreview else { return }
        isRunning = true
        refresh()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            onMainActor { self?.refresh() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        timer?.invalidate()
        timer = nil
        isScanning = false
        scanner.reset()
        snapshot = .empty
    }

    /// Scans now, unless a scan is already running.
    func refresh() {
        guard isRunning, !isScanning else { return }
        isScanning = true
        let generation = generation
        scanner.scan { [weak self] snapshot in
            onMainActor {
                guard let self, self.generation == generation else { return }
                self.isScanning = false
                if snapshot != self.snapshot { self.snapshot = snapshot }
            }
        }
    }

    /// Called when the tab is opened, so it never shows a minute-old figure
    /// to someone who just finished a turn and came to look.
    func refresh(ifOlderThan age: TimeInterval) {
        guard let scannedAt = snapshot.scannedAt else { return refresh() }
        if Date().timeIntervalSince(scannedAt) >= age { refresh() }
    }

    /// Publishes a fixed snapshot without reading anything, for the offscreen
    /// preview tool.
    func seedForPreview(_ snapshot: AgentUsageSnapshot) {
        stop()
        isPreview = true
        self.snapshot = snapshot
    }
}
