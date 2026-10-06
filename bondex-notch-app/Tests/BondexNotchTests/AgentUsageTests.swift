import Foundation
import XCTest
@testable import BondexNotch

// Fixture lines follow the shape each agent writes, trimmed to the fields that
// matter. The real lines carry much more (message content, tool output), which
// is exactly what the byte filter exists to skip.

private func claudeLine(
    id: String = "msg_01",
    request: String = "req_01",
    model: String = "claude-opus-5-5",
    timestamp: String = "2026-10-02T03:15:00.000Z",
    input: Int = 10,
    output: Int = 200,
    cacheWrite: Int = 1_000,
    cacheRead: Int = 50_000,
    longCacheWrite: Int? = nil,
    speed: String? = nil,
    cwd: String = "/Users/me/code/notch",
    session: String = "s1",
    extraUsage: String = ""
) -> String {
    var usage = """
    "input_tokens":\(input),"output_tokens":\(output),\
    "cache_creation_input_tokens":\(cacheWrite),"cache_read_input_tokens":\(cacheRead)
    """
    if let longCacheWrite {
        usage += #","cache_creation":{"ephemeral_5m_input_tokens":\#(cacheWrite - longCacheWrite),"ephemeral_1h_input_tokens":\#(longCacheWrite)}"#
    }
    if let speed { usage += #","speed":"\#(speed)""# }
    usage += extraUsage
    return """
    {"type":"assistant","timestamp":"\(timestamp)","requestId":"\(request)",\
    "cwd":"\(cwd)","sessionId":"\(session)",\
    "message":{"id":"\(id)","model":"\(model)","role":"assistant",\
    "content":[{"type":"text","text":"Done."}],"usage":{\(usage)}}}
    """
}

private func codexTokenCount(
    timestamp: String = "2026-10-02T03:20:00.000Z",
    total: (input: Int, cached: Int, output: Int)?,
    last: (input: Int, cached: Int, output: Int)?,
    limits: String? = nil
) -> String {
    func usage(_ value: (input: Int, cached: Int, output: Int)) -> String {
        """
        {"input_tokens":\(value.input),"cached_input_tokens":\(value.cached),\
        "output_tokens":\(value.output),"reasoning_output_tokens":\(value.output / 2),\
        "total_tokens":\(value.input + value.output)}
        """
    }
    var info = "null"
    if let total {
        info = #"{"total_token_usage":\#(usage(total))"#
        if let last { info += #","last_token_usage":\#(usage(last))"# }
        info += #","model_context_window":272000}"#
    }
    return """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count",\
    "info":\(info),"rate_limits":\(limits ?? "null")}}
    """
}

private let codexTurnContext = """
{"timestamp":"2026-10-02T03:19:00.000Z","type":"turn_context","payload":{"cwd":"/tmp","model":"gpt-5.1-codex"}}
"""

private func date(_ string: String) -> Date {
    LogTimestamp.parse(string)!
}

// MARK: - Timestamps and formatting

final class AgentUsageFormatTests: XCTestCase {

    func testTimestampsInEveryShapeTheAgentsWrite() {
        XCTAssertEqual(
            LogTimestamp.parse("2026-10-02T03:15:00.250Z")?.timeIntervalSince1970,
            1_790_910_900.25
        )
        XCTAssertEqual(
            LogTimestamp.parse("2026-10-02T10:15:00+07:00"),
            LogTimestamp.parse("2026-10-02T03:15:00Z")
        )
        XCTAssertEqual(
            LogTimestamp.parse("2026-10-02T03:15:00Z"),
            Date(timeIntervalSince1970: 1_790_910_900)
        )
        // Milliseconds since the epoch, as the Claude app writes them.
        XCTAssertEqual(
            LogTimestamp.parse(NSNumber(value: 1_790_910_900_000.0)),
            Date(timeIntervalSince1970: 1_790_910_900)
        )
        XCTAssertNil(LogTimestamp.parse("yesterday"))
        XCTAssertNil(LogTimestamp.parse(NSNumber(value: true)))
    }

    func testCompactTokenCounts() {
        XCTAssertEqual(950.compactTokenString, "950")
        XCTAssertEqual(12_400.compactTokenString, "12K")
        XCTAssertEqual(3_140_000.compactTokenString, "3.1M")
        XCTAssertEqual(50_000_000.compactTokenString, "50M")
        XCTAssertEqual(1_200_000_000.compactTokenString, "1.2B")
    }

    func testCountdownsAndRelativeTimes() {
        XCTAssertEqual((3 * 86_400 + 19 * 3_600 + 120.0).countdownString, "3d 19h")
        XCTAssertEqual((4 * 3_600 + 12 * 60.0).countdownString, "4h 12m")
        XCTAssertEqual(20.0.countdownString, "1m")

        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(now.addingTimeInterval(-30).shortRelativeString(from: now), "now")
        XCTAssertEqual(now.addingTimeInterval(-4 * 60).shortRelativeString(from: now), "4 min ago")
        XCTAssertEqual(now.addingTimeInterval(-2 * 3_600).shortRelativeString(from: now), "2 hr ago")
        XCTAssertEqual(now.addingTimeInterval(-86_400).shortRelativeString(from: now), "1 day ago")
    }

    func testModelNamesReadTheWayPeopleSayThem() {
        XCTAssertEqual(AgentModelName.display("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(AgentModelName.display("claude-sonnet-4-5-20250929"), "Sonnet 4.5")
        XCTAssertEqual(AgentModelName.display("claude-3-5-haiku-20241022"), "Haiku 3.5")
        XCTAssertEqual(AgentModelName.display("claude-opus-4"), "Opus 4")
        XCTAssertEqual(AgentModelName.display("gpt-5.1-codex-max"), "GPT-5.1 Codex Max")
        XCTAssertEqual(AgentModelName.display("gpt-6.1-sol"), "GPT-6.1 Sol")
        XCTAssertEqual(AgentModelName.display("gpt-reserve"), "gpt-reserve")
        XCTAssertEqual(AgentModelName.display("o4-mini"), "o4-mini")
    }

    func testProjectsAreNamedForTheRepositoryNotTheWorktree() {
        XCTAssertEqual(AgentProjectName.name(fromPath: "/Users/me/code/notch"), "notch")
        XCTAssertEqual(AgentProjectName.name(fromPath: "/Users/me/code/notch/"), "notch")
        XCTAssertEqual(AgentProjectName.name(fromPath: "/Users/me/code/notch/.claude/worktrees/fix-login"), "notch")
        XCTAssertEqual(AgentProjectName.name(fromPath: "/Users/me/code/api/.codex/worktrees/ab12/api"), "api")
        XCTAssertEqual(AgentProjectName.name(fromPath: NSHomeDirectory()), "~")
        XCTAssertNil(AgentProjectName.name(fromPath: "relative/path"))
    }

    func testClaudePlans() {
        XCTAssertEqual(ClaudePlanReader.planName(organizationType: "claude_pro", rateLimitTier: "default_claude_ai"), "Pro")
        XCTAssertEqual(ClaudePlanReader.planName(organizationType: "claude_max", rateLimitTier: "default_claude_max_20x"), "Max 20×")
        XCTAssertEqual(ClaudePlanReader.planName(organizationType: "claude_max", rateLimitTier: "default_claude_max_5x"), "Max 5×")
        XCTAssertEqual(ClaudePlanReader.planName(organizationType: "claude_enterprise", rateLimitTier: nil), "Enterprise")
        XCTAssertEqual(ClaudePlanReader.planName(organizationType: "claude_studio", rateLimitTier: nil), "Studio")
        XCTAssertNil(ClaudePlanReader.planName(organizationType: nil, rateLimitTier: nil))

        let profile = #"{"numStartups":3,"oauthAccount":{"emailAddress":"x@example.com","organizationType":"claude_pro","organizationRateLimitTier":"default_claude_ai"}}"#
        XCTAssertEqual(ClaudePlanReader.plan(from: Data(profile.utf8)), "Pro")
        XCTAssertNil(ClaudePlanReader.plan(from: Data(#"{"numStartups":3}"#.utf8)))
    }

    func testLimitWindowLabelsAndPace() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let week = UsageLimitWindow(
            id: "w", minutes: 10_080, usedPercent: 34,
            resetsAt: now.addingTimeInterval(3.5 * 86_400)
        )
        XCTAssertEqual(week.label, "Week")
        XCTAssertEqual(week.elapsedFraction(at: now)!, 0.5, accuracy: 0.0001)
        XCTAssertEqual(week.fraction, 0.34, accuracy: 0.0001)

        XCTAssertEqual(UsageLimitWindow(id: "s", minutes: 300, usedPercent: 0, resetsAt: nil).label, "Session")
        XCTAssertEqual(UsageLimitWindow(id: "o", minutes: 10_080, scope: "Opus", usedPercent: 1, resetsAt: nil).label, "Opus week")
        // No renewal time, no marker: a pace tick placed on a guess would be
        // read as a fact.
        XCTAssertNil(UsageLimitWindow(id: "s", minutes: 300, usedPercent: 10, resetsAt: nil).elapsedFraction(at: now))
    }
}

// MARK: - Pricing

final class AgentPricingTests: XCTestCase {

    func testModelIDsAreNormalisedBeforeLookup() {
        XCTAssertEqual(AgentPricing.normalized("claude-sonnet-4-5-20250929"), "claude-sonnet-4-5")
        XCTAssertEqual(AgentPricing.normalized("claude-opus-4-5@20251101"), "claude-opus-4-5")
        XCTAssertEqual(AgentPricing.normalized("us.anthropic.claude-haiku-4-5-20251001-v1:0"), "claude-haiku-4-5")
        XCTAssertEqual(AgentPricing.normalized("claude-sonnet-4-6[1m]"), "claude-sonnet-4-6")
        XCTAssertEqual(AgentPricing.normalized("openai/gpt-5.1-codex"), "gpt-5.1-codex")
        XCTAssertEqual(AgentPricing.normalized("claude-opus-5-5"), "claude-opus-5-5")
    }

    func testUnknownModelsAreNotPricedFromALookalike() {
        // A prefix match would price this as claude-opus-4 at $15/$75.
        XCTAssertNil(AgentPricing.rates(for: "claude-opus-4-9"))
        XCTAssertNil(AgentPricing.rates(for: "gpt-5.7-sol"))
        XCTAssertNil(AgentPricing.cost(model: "mystery", tokens: TokenTally(input: 1)))
    }

    func testCostCoversEveryTokenCategory() throws {
        // Opus 5.5: $4 in, $20 out, $5 5m write, $8 1h write, $0.20 read.
        let tokens = TokenTally(input: 1_000_000, output: 1_000_000, cacheWrite: 2_000_000, cacheRead: 10_000_000)
        let cost = try XCTUnwrap(AgentPricing.cost(model: "claude-opus-5-5", tokens: tokens, longCacheWrite: 1_000_000))
        XCTAssertEqual(cost, 4 + 20 + 5 + 8 + 2, accuracy: 0.000_1)
    }

    func testFastModeDoublesOnlyWhereItExists() throws {
        let tokens = TokenTally(input: 1_000_000)
        XCTAssertEqual(try XCTUnwrap(AgentPricing.cost(model: "claude-opus-5-5", tokens: tokens, fast: true)), 8, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(AgentPricing.cost(model: "claude-sonnet-5-5", tokens: tokens, fast: true)), 2, accuracy: 0.000_1)
    }

    func testCurrentModelsMatchPublishedPrices() throws {
        let sonnet = try XCTUnwrap(AgentPricing.rates(for: "claude-sonnet-5-5"))
        XCTAssertEqual(sonnet.input, 2)
        XCTAssertEqual(sonnet.output, 10)
        XCTAssertEqual(sonnet.cacheRead, 0.2)
        let fable = try XCTUnwrap(AgentPricing.rates(for: "claude-fable-5-1"))
        XCTAssertEqual(fable.input, 10)
        XCTAssertEqual(fable.cacheRead, 0.25)
        XCTAssertEqual(fable.cacheWrite, 12.5)
        XCTAssertEqual(try XCTUnwrap(AgentPricing.rates(for: "claude-haiku-4-5")).output, 5)
    }
}

// MARK: - Claude Code

final class ClaudeLogParserTests: XCTestCase {

    func testAssistantUsageIsReadAndPriced() throws {
        let record = try XCTUnwrap(ClaudeLogParser.record(from: Data(claudeLine(longCacheWrite: 400, speed: "fast").utf8)))
        XCTAssertEqual(record.key, "msg_01:req_01")
        XCTAssertEqual(record.model, "claude-opus-5-5")
        XCTAssertEqual(record.session, "s1")
        XCTAssertEqual(record.project, "notch")
        XCTAssertEqual(record.tally.tokens, TokenTally(input: 10, output: 200, cacheWrite: 1_000, cacheRead: 50_000))
        XCTAssertEqual(record.date, date("2026-10-02T03:15:00Z"))
        // Opus 5.5 in fast mode (×2): 10×$4 + 200×$20 + 600×$5 + 400×$8 + 50,000×$0.20.
        XCTAssertEqual(record.tally.cost, (40 + 4_000 + 3_000 + 3_200 + 10_000) / 1_000_000 * 2, accuracy: 1e-9)
    }

    func testEveryIterationIsBilledAtItsOwnModel() throws {
        // A refused attempt on Fable, answered by Opus 5.5: the top-level
        // counts cover only the answer, the iterations both attempts.
        let iterations = #","iterations":[{"type":"message","model":"claude-fable-5-1","input_tokens":1000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},{"type":"fallback_message","input_tokens":1000,"output_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}]"#
        let line = claudeLine(input: 1_000, output: 100, cacheWrite: 0, cacheRead: 0, extraUsage: iterations)
        let record = try XCTUnwrap(ClaudeLogParser.record(from: Data(line.utf8)))
        XCTAssertEqual(record.tally.tokens, TokenTally(input: 2_000, output: 100))
        // 1,000 × $10 (Fable) + 1,000 × $4 + 100 × $20 (Opus 5.5).
        XCTAssertEqual(record.tally.cost, (10_000 + 4_000 + 2_000) / 1_000_000, accuracy: 1e-9)
    }

    func testRegionalInferenceAndWebSearchAreCharged() throws {
        let extra = #","inference_geo":"us","server_tool_use":{"web_search_requests":3}"#
        let line = claudeLine(input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0, extraUsage: extra)
        let record = try XCTUnwrap(ClaudeLogParser.record(from: Data(line.utf8)))
        XCTAssertEqual(record.tally.cost, 4 * 1.1 + 0.03, accuracy: 1e-9)
    }

    func testSyntheticAndNonAssistantLinesAreSkipped() {
        XCTAssertNil(ClaudeLogParser.record(from: Data(claudeLine(model: "<synthetic>").utf8)))
        let user = #"{"type":"user","timestamp":"2026-10-02T03:15:00Z","message":{"role":"user","content":"usage"}}"#
        XCTAssertNil(ClaudeLogParser.record(from: Data(user.utf8)))
        XCTAssertNil(ClaudeLogParser.record(from: Data("not json".utf8)))
    }
}

// MARK: - Codex

final class CodexLogParserTests: XCTestCase {

    private let now = date("2026-10-02T04:00:00Z")

    func testUsageSplitsCachedInputAndTakesTheModelFromTurnContext() {
        var state = CodexFileState()
        XCTAssertEqual(CodexLogParser.events(from: Data(codexTurnContext.utf8), state: &state, now: now), [])
        XCTAssertEqual(state.model, "gpt-5.1-codex")

        let line = codexTokenCount(total: (10_000, 8_000, 500), last: (10_000, 8_000, 500))
        let events = CodexLogParser.events(from: Data(line.utf8), state: &state, now: now)
        XCTAssertEqual(state.project, "tmp")
        XCTAssertEqual(events, [.usage(
            date: date("2026-10-02T03:20:00Z"),
            model: "gpt-5.1-codex",
            project: "tmp",
            // Reasoning is part of output already and is not added again.
            tokens: TokenTally(input: 2_000, output: 500, cacheWrite: 0, cacheRead: 8_000)
        )])
    }

    func testARepeatedTotalIsNotCountedTwice() {
        var state = CodexFileState()
        let first = codexTokenCount(total: (1_000, 0, 100), last: (1_000, 0, 100))
        XCTAssertEqual(CodexLogParser.events(from: Data(first.utf8), state: &state, now: now).count, 1)
        // Codex re-sends the same total when only the rate limits moved.
        XCTAssertEqual(CodexLogParser.events(from: Data(first.utf8), state: &state, now: now), [])
    }

    func testOlderLogsWithOnlyARunningTotalCountTheGrowth() {
        var state = CodexFileState()
        _ = CodexLogParser.events(
            from: Data(codexTokenCount(total: (1_000, 200, 100), last: nil).utf8), state: &state, now: now
        )
        let events = CodexLogParser.events(
            from: Data(codexTokenCount(total: (1_500, 600, 160), last: nil).utf8), state: &state, now: now
        )
        XCTAssertEqual(events, [.usage(
            date: date("2026-10-02T03:20:00Z"),
            model: nil,
            project: nil,
            tokens: TokenTally(input: 100, output: 60, cacheWrite: 0, cacheRead: 400)
        )])
    }

    func testRateLimitsInBothResetFormats() throws {
        var state = CodexFileState()
        let limits = """
        {"limit_id":"codex","primary":{"used_percent":12.5,"window_minutes":300,"resets_in_seconds":3600},\
        "secondary":{"used_percent":5,"window_minutes":10080,"resets_at":1791432000},"plan_type":"plus"}
        """
        let events = CodexLogParser.events(
            from: Data(codexTokenCount(total: nil, last: nil, limits: limits).utf8), state: &state, now: now
        )
        guard case let .limits(reading, plan) = try XCTUnwrap(events.first) else {
            return XCTFail("Expected a limits event")
        }
        XCTAssertEqual(plan, "Plus")
        XCTAssertEqual(reading.source, .codexLog)
        XCTAssertEqual(reading.windows.map(\.label), ["Session", "Week"])
        XCTAssertEqual(reading.windows[0].usedPercent, 12.5)
        XCTAssertEqual(reading.windows[0].resetsAt, date("2026-10-02T04:20:00Z"))
        XCTAssertEqual(reading.windows[1].resetsAt, Date(timeIntervalSince1970: 1_791_432_000))
    }

    func testModelSpecificAllowancesDoNotReplaceThePlan() {
        var state = CodexFileState()
        let limits = #"{"limit_id":"gpt-5.6-cyber","primary":{"used_percent":90,"window_minutes":300}}"#
        XCTAssertEqual(
            CodexLogParser.events(from: Data(codexTokenCount(total: nil, last: nil, limits: limits).utf8), state: &state, now: now),
            []
        )
    }

    func testPlanNames() {
        XCTAssertEqual(CodexLogParser.planName("plus"), "Plus")
        XCTAssertEqual(CodexLogParser.planName("max_20x"), "Max 20x")
        XCTAssertNil(CodexLogParser.planName("unknown"))
        XCTAssertNil(CodexLogParser.planName(""))
    }
}

// MARK: - Claude app limits

final class ClaudeAppLimitsTests: XCTestCase {

    private func history(_ samples: [(String, [String: Double])], version: Int = 2) -> Data {
        let entries = samples.map { time, used -> [String: Any] in
            let milliseconds = date(time).timeIntervalSince1970 * 1_000
            return version == 1
                ? used.merging(["t": milliseconds]) { $1 }
                : ["t": milliseconds, "u": used, "org": "org-1"]
        }
        return try! JSONSerialization.data(withJSONObject: ["version": version, "samples": entries])
    }

    func testSessionRenewsFiveHoursAfterTheHourItStarted() throws {
        let data = history([
            ("2026-10-02T00:40:00Z", ["fh": 0, "sd": 30]),
            ("2026-10-02T01:10:00Z", ["fh": 4, "sd": 31]),
            ("2026-10-02T02:10:00Z", ["fh": 40, "sd": 33]),
            ("2026-10-02T03:10:00Z", ["fh": 64, "sd": 34])
        ])
        let samples = try XCTUnwrap(ClaudeAppLimitsReader.samples(from: data))
        let limits = try XCTUnwrap(ClaudeAppLimitsReader.limits(from: samples, now: date("2026-10-02T03:20:00Z")))

        let session = try XCTUnwrap(limits.windows.first { $0.minutes == 300 })
        XCTAssertEqual(session.usedPercent, 64)
        // First reading of the run was 01:10, so the session began at 01:00.
        XCTAssertEqual(session.resetsAt, date("2026-10-02T06:00:00Z"))
        XCTAssertEqual(limits.observedAt, date("2026-10-02T03:10:00Z"))
    }

    func testWeekRenewsAtTheLastDropPlusWholeWeeks() throws {
        let data = history([
            ("2026-09-20T09:30:00Z", ["sd": 88]),
            ("2026-09-20T10:20:00Z", ["sd": 2]),
            ("2026-10-02T03:10:00Z", ["sd": 34])
        ])
        let samples = try XCTUnwrap(ClaudeAppLimitsReader.samples(from: data))
        let limits = try XCTUnwrap(ClaudeAppLimitsReader.limits(from: samples, now: date("2026-10-02T03:20:00Z")))
        let week = try XCTUnwrap(limits.windows.first { $0.minutes == 10_080 })
        // Dropped between 09:30 and 10:20 on the 20th; renews weekly at 10:00.
        XCTAssertEqual(week.resetsAt, date("2026-10-04T10:00:00Z"))
    }

    func testAStaleSessionIsDroppedButTheWeekRemains() throws {
        let data = history([("2026-10-01T20:00:00Z", ["fh": 80, "sd": 34])])
        let samples = try XCTUnwrap(ClaudeAppLimitsReader.samples(from: data))
        let limits = try XCTUnwrap(ClaudeAppLimitsReader.limits(from: samples, now: date("2026-10-02T03:20:00Z")))
        XCTAssertEqual(limits.windows.map(\.minutes), [10_080])
    }

    func testModelWeeksAppearOnlyOnceUsed() throws {
        let data = history([("2026-10-02T03:10:00Z", ["fh": 10, "sd": 20, "so": 0, "sn": 7])])
        let samples = try XCTUnwrap(ClaudeAppLimitsReader.samples(from: data))
        let limits = try XCTUnwrap(ClaudeAppLimitsReader.limits(from: samples, now: date("2026-10-02T03:20:00Z")))
        XCTAssertEqual(limits.windows.map(\.label), ["Session", "Week", "Sonnet week"])
    }

    func testVersionOneAndUnknownVersions() throws {
        let v1 = history([("2026-10-02T03:10:00Z", ["fh": 10, "sd": 20])], version: 1)
        XCTAssertEqual(try XCTUnwrap(ClaudeAppLimitsReader.samples(from: v1)).first?.used["sd"], 20)

        let v9 = try JSONSerialization.data(withJSONObject: ["version": 9, "samples": []])
        XCTAssertNil(ClaudeAppLimitsReader.samples(from: v9))
    }
}

// MARK: - Ledger

final class AgentUsageLedgerTests: XCTestCase {

    private var root: URL!
    private let now = date("2026-10-02T04:00:00Z")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var roots: AgentUsageRoots {
        AgentUsageRoots(
            claude: [root.appendingPathComponent("claude")],
            codex: [root.appendingPathComponent("codex")],
            claudeAppHistory: root.appendingPathComponent("none.json")
        )
    }

    private func write(_ lines: [String], to path: String, append: Bool = false, newline: Bool = true) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + (newline ? "\n" : "")
        if append, let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: url)
        }
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testARequestRepeatedAcrossLinesAndFilesIsCountedOnce() throws {
        // One line per content block, then the same turn copied into a
        // resumed session's file.
        try write([claudeLine(), claudeLine()], to: "claude/project/a.jsonl")
        try write([claudeLine(), claudeLine(id: "msg_02", request: "req_02")], to: "claude/project/b.jsonl")

        let ledger = AgentUsageLedger()
        ledger.scan(roots, now: now)
        let today = ledger.snapshot(now: now, claudeLimits: nil, calendar: utc).summary(for: .today)
        XCTAssertEqual(today.byProvider[.claude]?.tokens.output, 400)
    }

    // MARK: Cache

    /// A restored ledger reports what the original did, and then reads only
    /// what was appended — not the month it already counted.
    func testARestoredLedgerCarriesOnWhereItStopped() throws {
        let path = "claude/project/a.jsonl"
        try write([claudeLine()], to: path)
        let original = AgentUsageLedger()
        original.scan(roots, now: now)
        let archive = original.archive(appVersion: "1.0 (1)", roots: roots)

        let encoded = try PropertyListEncoder().encode(archive)
        let decoded = try PropertyListDecoder().decode(AgentUsageLedger.Archive.self, from: encoded)
        let restored = try XCTUnwrap(
            AgentUsageLedger(archive: decoded, appVersion: "1.0 (1)", roots: roots, now: now)
        )
        XCTAssertEqual(
            restored.snapshot(now: now, claudeLimits: nil, calendar: utc).summary(for: .today),
            original.snapshot(now: now, claudeLimits: nil, calendar: utc).summary(for: .today)
        )
        XCTAssertFalse(restored.hasUnsavedChanges)

        // Nothing new: nothing is re-counted.
        restored.scan(roots, now: now)
        XCTAssertEqual(
            restored.snapshot(now: now, claudeLimits: nil, calendar: utc).summary(for: .today).total.tokens.output,
            200
        )

        try write([claudeLine(id: "msg_02", request: "req_02")], to: path, append: true)
        restored.scan(roots, now: now)
        XCTAssertEqual(
            restored.snapshot(now: now, claudeLimits: nil, calendar: utc).summary(for: .today).total.tokens.output,
            400
        )
        XCTAssertTrue(restored.hasUnsavedChanges)
    }

    /// A turn copied into a resumed session's new file must not count twice
    /// just because the first count happened before a restart.
    func testARestoredLedgerStillRecognisesRequestsItCounted() throws {
        try write([claudeLine()], to: "claude/project/a.jsonl")
        let original = AgentUsageLedger()
        original.scan(roots, now: now)
        let restored = try XCTUnwrap(AgentUsageLedger(
            archive: original.archive(appVersion: "1", roots: roots),
            appVersion: "1", roots: roots, now: now
        ))

        try write([claudeLine()], to: "claude/project/resumed.jsonl")
        restored.scan(roots, now: now)
        XCTAssertEqual(
            restored.snapshot(now: now, claudeLimits: nil, calendar: utc).summary(for: .today).total.tokens.output,
            200
        )
    }

    /// Another build may parse or price differently; other folders are other
    /// figures. Either one starts afresh.
    func testACacheFromAnotherBuildOrFoldersIsIgnored() {
        let archive = AgentUsageLedger().archive(appVersion: "1.0 (1)", roots: roots)
        XCTAssertNil(AgentUsageLedger(archive: archive, appVersion: "1.1 (2)", roots: roots, now: now))
        let elsewhere = AgentUsageRoots(
            claude: [root.appendingPathComponent("other")],
            codex: [],
            claudeAppHistory: root.appendingPathComponent("none.json")
        )
        XCTAssertNil(AgentUsageLedger(archive: archive, appVersion: "1.0 (1)", roots: elsewhere, now: now))
    }

    /// An idle scan changes nothing, so it must not rewrite the cache.
    func testAnIdleScanHasNothingToSave() throws {
        try write([claudeLine()], to: "claude/project/a.jsonl")
        let ledger = AgentUsageLedger()
        ledger.scan(roots, now: now)
        ledger.markSaved()
        ledger.scan(roots, now: now)
        XCTAssertFalse(ledger.hasUnsavedChanges)
    }

    func testAHalfWrittenLineWaitsForItsNewline() throws {
        let path = "claude/project/live.jsonl"
        try write([claudeLine()], to: path)
        try write([String(claudeLine(id: "msg_02", request: "req_02").prefix(40))], to: path, append: true, newline: false)

        let ledger = AgentUsageLedger()
        ledger.scan(roots, now: now)
        XCTAssertEqual(ledger.snapshot(now: now, claudeLimits: nil, calendar: utc).summary(for: .today).total.tokens.output, 200)

        // The agent finishes the line; only now is it read, and read whole.
        let rest = String(claudeLine(id: "msg_02", request: "req_02").dropFirst(40))
        try write([rest], to: path, append: true)
        ledger.scan(roots, now: now)
        XCTAssertEqual(ledger.snapshot(now: now, claudeLimits: nil, calendar: utc).summary(for: .today).total.tokens.output, 400)
    }

    func testCodexUsageAndLimitsFlowIntoTheSnapshot() throws {
        let limits = #"{"primary":{"used_percent":20,"window_minutes":300,"resets_in_seconds":600},"plan_type":"pro"}"#
        try write([
            codexTurnContext,
            codexTokenCount(total: (10_000, 8_000, 500), last: (10_000, 8_000, 500), limits: limits)
        ], to: "codex/2026/10/02/rollout-1.jsonl")

        let ledger = AgentUsageLedger()
        ledger.scan(roots, now: now)
        let snapshot = ledger.snapshot(now: now, claudeLimits: nil, calendar: utc)

        let codex = snapshot.status(for: .codex)
        XCTAssertTrue(codex.hasLogs)
        XCTAssertEqual(codex.plan, "Pro")
        XCTAssertEqual(codex.limits?.windows.first?.usedPercent, 20)
        XCTAssertEqual(codex.lastActivity, date("2026-10-02T03:20:00Z"))
        XCTAssertEqual(snapshot.visibleProviders, [.codex])

        let today = snapshot.summary(for: .today)
        let tally = try XCTUnwrap(today.byProvider[.codex])
        XCTAssertEqual(tally.tokens.total, 10_500)
        // gpt-5.1-codex: 2,000 × $1.25 + 8,000 × $0.125 + 500 × $10, per million.
        XCTAssertEqual(tally.cost, 0.0085, accuracy: 0.000_001)
        XCTAssertEqual(today.cacheShare!, 0.8, accuracy: 0.000_1)
    }

    func testUnpricedModelsMakeTheTotalALowerBound() throws {
        try write([claudeLine(model: "claude-opus-9")], to: "claude/p/a.jsonl")
        let ledger = AgentUsageLedger()
        ledger.scan(roots, now: now)
        let today = ledger.snapshot(now: now, claudeLimits: nil, calendar: utc).summary(for: .today)
        XCTAssertTrue(today.isLowerBound)
        XCTAssertEqual(today.total.cost, 0)
        XCTAssertEqual(today.total.tokens.output, 200)
    }

    func testTrendBarsCoverTheRangeAndLandInTheRightHour() throws {
        try write([
            claudeLine(id: "a", request: "1", timestamp: "2026-10-02T01:05:00Z"),
            claudeLine(id: "b", request: "2", timestamp: "2026-10-02T03:59:00Z"),
            // Yesterday: in the week, not in today.
            claudeLine(id: "c", request: "3", timestamp: "2026-10-01T22:00:00Z"),
            // Past the 31-day horizon: ignored entirely.
            claudeLine(id: "d", request: "4", timestamp: "2026-08-01T12:00:00Z")
        ], to: "claude/p/a.jsonl")

        let ledger = AgentUsageLedger()
        ledger.scan(roots, now: now)
        let snapshot = ledger.snapshot(now: now, claudeLimits: nil, calendar: utc)

        let today = snapshot.summary(for: .today)
        XCTAssertEqual(today.trend.count, 24)
        XCTAssertEqual(today.trend[1].tokens[.claude], 51_210)
        XCTAssertEqual(today.trend[3].tokens[.claude], 51_210)
        XCTAssertEqual(today.total.tokens.output, 400)

        let week = snapshot.summary(for: .week)
        XCTAssertEqual(week.trend.count, 7)
        XCTAssertEqual(week.trend.last?.start, date("2026-10-02T00:00:00Z"))
        XCTAssertEqual(week.total.tokens.output, 600)
        XCTAssertEqual(snapshot.summary(for: .month).trend.count, 30)
    }

    func testASessionKeepsTheProjectItStartedIn() throws {
        try write([
            claudeLine(id: "a", request: "1", timestamp: "2026-10-02T01:00:00Z", cwd: "/Users/me/code/notch"),
            // Claude `cd`s into a subfolder; the session is still the notch project.
            claudeLine(id: "b", request: "2", timestamp: "2026-10-02T01:05:00Z", cwd: "/Users/me/code/notch/app"),
            claudeLine(id: "c", request: "3", model: "claude-sonnet-5-5", timestamp: "2026-10-02T02:00:00Z", cwd: "/Users/me/code/site", session: "s2")
        ], to: "claude/p/a.jsonl")

        let ledger = AgentUsageLedger()
        ledger.scan(roots, now: now)
        let snapshot = ledger.snapshot(now: now, claudeLimits: nil, claudePlan: "Pro", calendar: utc)

        XCTAssertEqual(snapshot.sessions.map(\.project), ["site", "notch"])
        XCTAssertEqual(snapshot.sessions.first?.model, "claude-sonnet-5-5")
        XCTAssertEqual(snapshot.status(for: .claude).plan, "Pro")
        XCTAssertEqual(snapshot.status(for: .claude).model, "claude-sonnet-5-5")

        let today = snapshot.summary(for: .today)
        XCTAssertEqual(today.byProject.map(\.name), ["notch", "site"])
        XCTAssertEqual(today.byProject.first?.tally.tokens.output, 400)
        XCTAssertEqual(Set(today.byModel.map(\.name)), ["Opus 5.5", "Sonnet 5.5"])
        XCTAssertEqual(today.byModel.first?.name, "Opus 5.5")
    }

    func testOnlyLinesWithAMarkerAreDecoded() {
        let data = Data("""
        {"type":"user","content":"x"}
        \(claudeLine())
        {"type":"assistant","partial
        """.utf8)
        var seen: [Data] = []
        let consumed = AgentUsageLedger.forEachLine(in: data, containingAny: [ClaudeLogParser.marker]) {
            seen.append($0)
        }
        XCTAssertEqual(seen.count, 1)
        // The trailing fragment has no newline yet and is left for next time.
        XCTAssertEqual(consumed, data.count - #"{"type":"assistant","partial"#.utf8.count)
    }
}
