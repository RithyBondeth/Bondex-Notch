import Foundation

// Pure readers for the files coding agents leave on this Mac. Nothing here
// touches the filesystem or the network: each takes the bytes and returns what
// they mean, so every format rule is testable against a fixture line.
//
// The formats belong to the agents, not to Bondex, and they change between
// releases. Every reader therefore skips what it does not recognise rather than
// guessing: a line it cannot read costs one data point, while a misread one
// would put a wrong number on screen with nothing to say it was wrong.

// MARK: - Timestamps

enum LogTimestamp {

    /// Parses the ISO 8601 timestamps both agents write, e.g.
    /// `2026-10-02T08:15:42.123Z` or `2026-10-02T15:15:42+07:00`.
    ///
    /// Hand-rolled because it runs once per log line, and the first scan can
    /// cover hundreds of thousands of them: `ISO8601FormatStyle` is several
    /// times slower for a format this narrow. Anything unusual falls through to
    /// it rather than being rejected.
    static func parse(_ value: Any?) -> Date? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let raw = number.doubleValue
            guard raw.isFinite, raw > 0 else { return nil }
            // Milliseconds once the value is past the year 33658 in seconds.
            return Date(timeIntervalSince1970: raw > 1e12 ? raw / 1_000 : raw)
        }
        guard let string = value as? String else { return nil }
        return fast(string) ?? (try? Date(string, strategy: .iso8601))
            ?? (try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    private static func fast(_ string: String) -> Date? {
        let bytes = Array(string.utf8)
        guard bytes.count >= 19,
              bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"),
              bytes[10] == UInt8(ascii: "T") || bytes[10] == UInt8(ascii: " "),
              bytes[13] == UInt8(ascii: ":"), bytes[16] == UInt8(ascii: ":"),
              let year = digits(bytes, 0, 4), let month = digits(bytes, 5, 7),
              let day = digits(bytes, 8, 10), let hour = digits(bytes, 11, 13),
              let minute = digits(bytes, 14, 16), let second = digits(bytes, 17, 19)
        else { return nil }

        var index = 19
        var fraction = 0.0
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            var scale = 0.1
            while index < bytes.count, let digit = digit(bytes[index]) {
                fraction += Double(digit) * scale
                scale /= 10
                index += 1
            }
        }

        var offset = 0
        if index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "Z"), UInt8(ascii: "z"):
                index += 1
            case UInt8(ascii: "+"), UInt8(ascii: "-"):
                let sign = bytes[index] == UInt8(ascii: "-") ? -1 : 1
                let rest = Array(bytes[(index + 1)...]).filter { $0 != UInt8(ascii: ":") }
                guard rest.count == 4, let hours = digits(rest, 0, 2), let minutes = digits(rest, 2, 4)
                else { return nil }
                offset = sign * (hours * 3_600 + minutes * 60)
                index = bytes.count
            default:
                return nil
            }
        }
        guard index == bytes.count else { return nil }

        var components = tm()
        components.tm_year = Int32(year - 1900)
        components.tm_mon = Int32(month - 1)
        components.tm_mday = Int32(day)
        components.tm_hour = Int32(hour)
        components.tm_min = Int32(minute)
        components.tm_sec = Int32(second)
        let seconds = timegm(&components)
        guard seconds != -1 else { return nil }
        return Date(timeIntervalSince1970: Double(seconds) + fraction - Double(offset))
    }

    private static func digit(_ byte: UInt8) -> Int? {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") ? Int(byte - UInt8(ascii: "0")) : nil
    }

    private static func digits(_ bytes: [UInt8], _ start: Int, _ end: Int) -> Int? {
        var value = 0
        for index in start..<end {
            guard let digit = digit(bytes[index]) else { return nil }
            value = value * 10 + digit
        }
        return value
    }
}

// MARK: - JSON helpers

enum LogJSON {
    static func object(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    /// A non-negative integer, or zero. Token counts are never negative, and a
    /// boolean decoded as `NSNumber` must not be read as a count of one.
    static func count(_ value: Any?) -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return 0 }
        let raw = number.doubleValue
        guard raw.isFinite, raw > 0 else { return 0 }
        return Int(min(raw, Double(Int.max / 4)))
    }

    static func double(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
}

// MARK: - Claude Code

/// One billed request, read from a Claude Code session log
/// (`~/.claude/projects/<project>/<session>.jsonl`).
struct ClaudeUsageRecord: Equatable {
    /// Identifies the request across files. Claude Code writes one line per
    /// content block, each repeating the same usage, and copies earlier turns
    /// into the new file when a session is resumed — so the same request can
    /// appear many times. Nil only for lines from versions that wrote neither
    /// identifier; those cannot be deduplicated and are counted as they come.
    let key: String?
    let date: Date
    let model: String
    /// Claude Code's session ID, which subagent logs share with their parent.
    let session: String?
    let project: String?
    /// Tokens across every attempt the request made, priced.
    let tally: UsageTally
}

enum ClaudeLogParser {

    /// Cheap byte filter run before any JSON is decoded. Most of a session log
    /// is tool output and file contents, and none of those lines carry usage.
    static let marker = Array(#""usage""#.utf8)

    static func record(from line: Data) -> ClaudeUsageRecord? {
        guard let json = LogJSON.object(line),
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String,
              // `<synthetic>` marks messages Claude Code wrote itself, such as
              // an API error shown in the transcript. Nothing was billed.
              !model.isEmpty, !model.hasPrefix("<"),
              let date = LogTimestamp.parse(json["timestamp"])
        else { return nil }

        let tally = self.tally(usage, model: model)
        guard tally.tokens.total > 0 else { return nil }

        let messageID = message["id"] as? String ?? ""
        let requestID = json["requestId"] as? String ?? ""
        let key = messageID.isEmpty && requestID.isEmpty ? nil : "\(messageID):\(requestID)"

        return ClaudeUsageRecord(
            key: key,
            date: date,
            model: model,
            session: json["sessionId"] as? String,
            project: (json["cwd"] as? String).flatMap(AgentProjectName.name(fromPath:)),
            tally: tally
        )
    }

    /// Prices one request's usage the way the API bills it.
    ///
    /// `iterations`, when present, lists every attempt the request made — a
    /// compaction pass, a refused attempt before a fallback model answered —
    /// each billed in full, while the top-level counts cover only the attempt
    /// that produced the reply. Summing the iterations is what the bill does.
    /// A fallback attempt names its own model, and is priced at that model's
    /// rates.
    static func tally(_ usage: [String: Any], model: String) -> UsageTally {
        let attempts = (usage["iterations"] as? [[String: Any]]).flatMap { $0.isEmpty ? nil : $0 } ?? [usage]
        let fast = usage["speed"] as? String == "fast"
        let regional = usage["inference_geo"] as? String == "us" ? AgentPricing.usOnlyMultiplier : 1

        var result = UsageTally()
        for attempt in attempts {
            let tokens = TokenTally(
                input: LogJSON.count(attempt["input_tokens"]),
                output: LogJSON.count(attempt["output_tokens"]),
                cacheWrite: LogJSON.count(attempt["cache_creation_input_tokens"]),
                cacheRead: LogJSON.count(attempt["cache_read_input_tokens"])
            )
            let longWrite = LogJSON.count((attempt["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"])
            let attemptModel = (attempt["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? model
            result.tokens += tokens
            if let cost = AgentPricing.cost(model: attemptModel, tokens: tokens, longCacheWrite: longWrite, fast: fast) {
                result.cost += cost * regional
            } else {
                result.unpricedTokens += tokens.total
            }
        }
        let searches = LogJSON.count((usage["server_tool_use"] as? [String: Any])?["web_search_requests"])
        result.cost += Double(searches) * AgentPricing.webSearchPerRequest
        return result
    }
}

// MARK: - Codex

/// What a Codex session log has said so far, carried between lines of one file.
struct CodexFileState: Equatable {
    /// Set by `turn_context` lines; usage lines do not repeat it.
    var model: String?
    /// The folder the session started in, from `session_meta` or the first
    /// `turn_context`.
    var project: String?
    /// The running total from the previous `token_count`. Codex re-sends the
    /// same total whenever only the rate limits changed, so usage is counted
    /// only when the total moves.
    var lastTotal: TokenTally?
}

enum CodexLogEvent: Equatable {
    case usage(date: Date, model: String?, project: String?, tokens: TokenTally)
    case limits(ProviderLimits, plan: String?)
}

/// Reads Codex rollout logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`).
enum CodexLogParser {

    static let markers = [
        Array(#""token_count""#.utf8),
        Array(#""turn_context""#.utf8),
        Array(#""session_meta""#.utf8)
    ]

    static func events(from line: Data, state: inout CodexFileState, now: Date) -> [CodexLogEvent] {
        guard let json = LogJSON.object(line),
              let payload = json["payload"] as? [String: Any]
        else { return [] }

        switch json["type"] as? String {
        case "turn_context", "session_meta":
            if let model = payload["model"] as? String, !model.isEmpty { state.model = model }
            // The folder the session started in names it for its whole life,
            // even if a turn later runs somewhere below it.
            if state.project == nil,
               let project = (payload["cwd"] as? String).flatMap(AgentProjectName.name(fromPath:)) {
                state.project = project
            }
            return []
        case "event_msg" where payload["type"] as? String == "token_count":
            let date = LogTimestamp.parse(json["timestamp"]) ?? now
            var events: [CodexLogEvent] = []
            if let usage = usage(payload["info"] as? [String: Any], state: &state) {
                events.append(.usage(date: date, model: state.model, project: state.project, tokens: usage))
            }
            if let limits = payload["rate_limits"] as? [String: Any], let reading = self.limits(limits, at: date) {
                events.append(reading)
            }
            return events
        default:
            return []
        }
    }

    /// The tokens one `token_count` adds.
    ///
    /// Prefers `last_token_usage`, the request on its own, which stays right
    /// even when the running total restarts partway through a file. Older logs
    /// carry only the total, so the request is what it grew by.
    private static func usage(_ info: [String: Any]?, state: inout CodexFileState) -> TokenTally? {
        guard let info, let raw = info["total_token_usage"] as? [String: Any] else { return nil }
        let total = tally(raw)
        let previous = state.lastTotal
        state.lastTotal = total
        guard total != previous else { return nil }

        if let last = info["last_token_usage"] as? [String: Any] {
            let tokens = tally(last)
            return tokens.total > 0 ? tokens : nil
        }
        guard let previous else { return total.total > 0 ? total : nil }
        let delta = TokenTally(
            input: max(total.input - previous.input, 0),
            output: max(total.output - previous.output, 0),
            cacheWrite: max(total.cacheWrite - previous.cacheWrite, 0),
            cacheRead: max(total.cacheRead - previous.cacheRead, 0)
        )
        return delta.total > 0 ? delta : nil
    }

    /// OpenAI counts cached input as part of input; this splits it out.
    static func tally(_ usage: [String: Any]) -> TokenTally {
        let input = LogJSON.count(usage["input_tokens"])
        let cached = min(input, LogJSON.count(usage["cached_input_tokens"]))
        let written = min(input - cached, LogJSON.count(usage["cache_write_input_tokens"]))
        // `output_tokens` already includes reasoning; `reasoning_output_tokens`
        // is a breakdown of it and must not be added again.
        return TokenTally(
            input: input - cached - written,
            output: LogJSON.count(usage["output_tokens"]),
            cacheWrite: written,
            cacheRead: cached
        )
    }

    /// The plan-wide allowances from one `rate_limits` snapshot.
    ///
    /// Codex can log a separate allowance per model, named by `limit_id`; only
    /// the main one ("codex", or unnamed in older logs) describes the plan.
    static func limits(_ raw: [String: Any], at date: Date) -> CodexLogEvent? {
        let id = (raw["limit_id"] as? String ?? "").lowercased()
        guard id.isEmpty || id == "codex" else { return nil }

        var windows: [UsageLimitWindow] = []
        for (name, fallbackMinutes) in [("primary", 300), ("secondary", 10_080)] {
            guard let window = raw[name] as? [String: Any],
                  let used = LogJSON.double(window["used_percent"]) else { continue }
            let minutes = LogJSON.double(window["window_minutes"]).map { Int($0) } ?? fallbackMinutes
            var resetsAt: Date?
            if let absolute = LogJSON.double(window["resets_at"]), absolute > 0 {
                resetsAt = Date(timeIntervalSince1970: absolute > 1e12 ? absolute / 1_000 : absolute)
            } else if let relative = LogJSON.double(window["resets_in_seconds"]), relative >= 0 {
                resetsAt = date.addingTimeInterval(relative)
            }
            windows.append(UsageLimitWindow(
                id: "codex.\(name)",
                minutes: minutes,
                usedPercent: min(max(used, 0), 100),
                resetsAt: resetsAt
            ))
        }
        guard !windows.isEmpty else { return nil }

        let plan = (raw["plan_type"] as? String).flatMap(planName)
        return .limits(ProviderLimits(windows: windows, observedAt: date, source: .codexLog), plan: plan)
    }

    static func planName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased() != "unknown" else { return nil }
        return trimmed.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

// MARK: - Claude desktop app

/// Plan limits as recorded by the Claude desktop app.
///
/// Claude Code's logs carry tokens but not the plan's allowances. The desktop
/// app checks those itself while its menu bar item is on, and keeps a rolling
/// history of percentages in
/// `~/Library/Application Support/Claude/plan-usage-history.json`. Reading that
/// file needs no sign-in and sends nothing; when it is absent, the Claude card
/// says where limits come from instead of showing a guess.
enum ClaudeAppLimitsReader {

    struct Sample: Equatable {
        let date: Date
        let organization: String?
        /// Percent used, keyed by the file's short window names.
        let used: [String: Double]
    }

    /// The file's window keys, the window each one is, and its display scope.
    static let windows: [(key: String, minutes: Int, scope: String?)] = [
        ("fh", 300, nil),
        ("sd", 10_080, nil),
        ("so", 10_080, "Opus"),
        ("sn", 10_080, "Sonnet")
    ]

    static let maximumFileSize = 4 << 20

    static func historyURL(home: URL) -> URL {
        home.appendingPathComponent(
            "Library/Application Support/Claude/plan-usage-history.json",
            isDirectory: false
        )
    }

    /// Readings oldest first, or nil for a file in a shape this does not know.
    static func samples(from data: Data) -> [Sample]? {
        guard data.count <= maximumFileSize,
              let json = LogJSON.object(data),
              let version = LogJSON.double(json["version"]).map(Int.init),
              version == 1 || version == 2,
              let entries = json["samples"] as? [[String: Any]]
        else { return nil }

        let samples: [Sample] = entries.compactMap { entry in
            guard let date = LogTimestamp.parse(entry["t"]) else { return nil }
            // Version 1 kept the values beside the time; version 2 nests them.
            let values = version == 1 ? entry : (entry["u"] as? [String: Any] ?? [:])
            var used: [String: Double] = [:]
            for window in windows {
                if let value = LogJSON.double(values[window.key]) {
                    used[window.key] = min(max(value, 0), 100)
                }
            }
            return Sample(date: date, organization: entry["org"] as? String, used: used)
        }
        return samples.sorted { $0.date < $1.date }
    }

    /// The newest reading as limit windows, with renewal times where the
    /// history allows them to be worked out.
    static func limits(from all: [Sample], now: Date) -> ProviderLimits? {
        guard let latest = all.last,
              latest.date <= now.addingTimeInterval(300),
              now.timeIntervalSince(latest.date) < 7 * 86_400
        else { return nil }
        // The app may have been signed in to another account earlier.
        let history = all.filter { $0.organization == latest.organization }

        var result: [UsageLimitWindow] = []
        for window in windows {
            guard let used = latest.used[window.key] else { continue }
            // Model-specific weeks only earn a row once they are in use.
            if window.scope != nil, used <= 0 { continue }
            let length = TimeInterval(window.minutes) * 60
            let resetsAt = window.minutes == 300
                ? sessionReset(history, length: length)
                : weeklyReset(history, key: window.key, length: length, now: now)

            // A session reading older than a session cannot describe the
            // current one, and neither can a window known to have renewed.
            if window.minutes == 300, now.timeIntervalSince(latest.date) >= length { continue }
            if let resetsAt, resetsAt <= now { continue }

            result.append(UsageLimitWindow(
                id: "claude.\(window.key)",
                minutes: window.minutes,
                scope: window.scope,
                usedPercent: used,
                resetsAt: resetsAt
            ))
        }
        guard !result.isEmpty else { return nil }
        return ProviderLimits(windows: result, observedAt: latest.date, source: .claudeApp)
    }

    /// A five-hour session starts on the hour of its first request.
    ///
    /// The history shows the session as a run of readings that only rise; the
    /// run's first reading bounds the start from above. Placing the start there
    /// can only make the countdown *later* than the truth, never claim a renewal
    /// that has not happened yet.
    private static func sessionReset(_ history: [Sample], length: TimeInterval) -> Date? {
        guard var first = history.indices.last, (history[first].used["fh"] ?? 0) > 0 else { return nil }
        let latest = history[first].date
        while first > 0,
              let before = history[first - 1].used["fh"], before > 0,
              before <= (history[first].used["fh"] ?? 0) + 0.5,
              latest.timeIntervalSince(history[first - 1].date) < length {
            first -= 1
        }
        return hourStart(history[first].date).addingTimeInterval(length)
    }

    /// A weekly allowance renews at the same moment each week. The newest drop
    /// in the history is one such moment; the next one after now follows.
    private static func weeklyReset(_ history: [Sample], key: String, length: TimeInterval, now: Date) -> Date? {
        for index in history.indices.dropFirst().reversed() {
            guard let before = history[index - 1].used[key],
                  let after = history[index].used[key],
                  after + 1 < before else { continue }
            var moment = hourStart(history[index].date)
            if moment <= history[index - 1].date { moment = history[index].date }
            while moment <= now { moment.addTimeInterval(length) }
            return moment
        }
        return nil
    }

    private static func hourStart(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3_600).rounded(.down) * 3_600)
    }
}

// MARK: - Claude plan

/// The Claude subscription, from the account profile Claude Code caches in
/// `~/.claude.json`.
///
/// Only the plan fields are read; the rest of that file — the account's name
/// and email, project history — is never kept. No credentials live there:
/// Claude Code keeps its tokens in the Keychain.
enum ClaudePlanReader {

    static func plan(from data: Data) -> String? {
        guard let json = LogJSON.object(data),
              let account = json["oauthAccount"] as? [String: Any] else { return nil }
        return planName(
            organizationType: account["organizationType"] as? String,
            rateLimitTier: account["organizationRateLimitTier"] as? String
                ?? account["userRateLimitTier"] as? String
        )
    }

    /// `claude_max` with a `default_claude_max_20x` tier is "Max 20×";
    /// `claude_pro` is "Pro". A type this does not know still shows its own
    /// name rather than nothing.
    static func planName(organizationType: String?, rateLimitTier: String?) -> String? {
        let type = (organizationType ?? "").lowercased()
        let tier = (rateLimitTier ?? "").lowercased()
        let known: [(match: String, name: String)] = [
            ("max_20x", "Max 20×"), ("max_5x", "Max 5×"), ("max", "Max"),
            ("enterprise", "Enterprise"), ("team", "Team"), ("pro", "Pro")
        ]
        if let plan = known.first(where: { tier.contains($0.match) || type.contains($0.match) }) {
            return plan.name
        }
        let name = type.replacingOccurrences(of: "claude_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name.prefix(1).uppercased() + name.dropFirst()
    }
}
