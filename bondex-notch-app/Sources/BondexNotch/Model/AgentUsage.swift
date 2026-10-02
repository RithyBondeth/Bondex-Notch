import Foundation

/// A coding agent whose usage Bondex can read from this Mac.
///
/// Closed, unlike `AgentKind`: usage depends on knowing where each tool keeps
/// its logs and what their lines mean, and a guess at either would produce
/// numbers that look authoritative and are not.
enum UsageProvider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var kind: AgentKind {
        switch self {
        case .claude: return .claude
        case .codex: return .codex
        }
    }

    var displayName: String { kind.displayName }
}

/// Token counts in the shape both providers bill by.
///
/// `input` is *uncached* input only. OpenAI reports cached tokens as a subset
/// of input, so the Codex parser subtracts them before they arrive here; that
/// keeps one meaning per field and lets every total be a plain sum.
struct TokenTally: Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0

    var total: Int { input + output + cacheWrite + cacheRead }

    /// Every token the model read, which is what "from cache" is a share of.
    var prompt: Int { input + cacheWrite + cacheRead }

    static func + (lhs: TokenTally, rhs: TokenTally) -> TokenTally {
        TokenTally(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }

    static func += (lhs: inout TokenTally, rhs: TokenTally) { lhs = lhs + rhs }
}

/// Tokens plus what they would have cost at public API prices.
struct UsageTally: Equatable, Sendable {
    var tokens = TokenTally()
    var cost: Double = 0
    /// Tokens from a model missing from the price table. They are counted but
    /// not priced, which turns the spend figure into a lower bound.
    var unpricedTokens = 0

    static func + (lhs: UsageTally, rhs: UsageTally) -> UsageTally {
        UsageTally(
            tokens: lhs.tokens + rhs.tokens,
            cost: lhs.cost + rhs.cost,
            unpricedTokens: lhs.unpricedTokens + rhs.unpricedTokens
        )
    }

    static func += (lhs: inout UsageTally, rhs: UsageTally) { lhs = lhs + rhs }
}

/// One plan allowance: a share used of a window that renews on a schedule.
struct UsageLimitWindow: Identifiable, Equatable, Sendable {
    let id: String
    /// Length of the window, which is also how it is named.
    let minutes: Int
    /// A model-specific allowance, e.g. "Opus". Nil for the plan-wide one.
    var scope: String?
    let usedPercent: Double
    /// Nil when the source does not say and cannot be inferred.
    let resetsAt: Date?

    var fraction: Double { min(max(usedPercent / 100, 0), 1) }

    var label: String {
        let base: String
        switch minutes {
        case ..<1: base = "Window"
        case ..<60: base = "\(minutes)m"
        case 300: base = "Session"
        case 10_080: base = "Week"
        case ..<1_440: base = "\(minutes / 60)h"
        default: base = "\(minutes / 1_440)d"
        }
        return scope.map { "\($0) \(base.lowercased())" } ?? base
    }

    /// How far through the window `now` is, for the pace marker on the bar.
    ///
    /// Usage left of the marker is under pace for the window; right of it
    /// means the allowance runs out before it renews. Nil without a renewal
    /// time, because a marker placed on a guess would be read as a fact.
    func elapsedFraction(at now: Date) -> Double? {
        guard let resetsAt, minutes > 0 else { return nil }
        let length = TimeInterval(minutes) * 60
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0, remaining <= length else { return nil }
        return 1 - remaining / length
    }
}

/// The latest reading of a provider's plan allowances.
struct ProviderLimits: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// The Claude desktop app's own record of the plan's limits.
        case claudeApp
        /// A rate-limit snapshot Codex writes into its session log each turn.
        case codexLog
    }

    var windows: [UsageLimitWindow]
    /// When the source took the reading. A log only updates while the agent
    /// runs, so this is shown once it is no longer fresh.
    var observedAt: Date
    var source: Source
}

enum UsageRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "7 Days"
        case .month: return "30 Days"
        }
    }

    /// Number of bars in the trend, and whether each covers an hour or a day.
    var barCount: Int {
        switch self {
        case .today: return 24
        case .week: return 7
        case .month: return 30
        }
    }

    var barsAreHourly: Bool { self == .today }
}

/// One bar in the trend chart.
struct UsageTrendBar: Identifiable, Equatable, Sendable {
    let start: Date
    var tokens: [UsageProvider: Int] = [:]
    var cost: [UsageProvider: Double] = [:]

    var id: Date { start }
    var totalTokens: Int { tokens.values.reduce(0, +) }
}

/// One line of a breakdown: a project or a model and what it used.
struct UsageBreakdownItem: Identifiable, Equatable, Sendable {
    let name: String
    /// The agent that did most of it, which decides the row's colour.
    var provider: UsageProvider
    var tally: UsageTally

    var id: String { name }
}

/// One agent session: where it ran and what it ran on.
struct AgentSession: Identifiable, Equatable, Sendable {
    let id: String
    let provider: UsageProvider
    /// The folder the agent ran in, by name. Nil when the log did not say.
    var project: String?
    /// Raw model ID from the log; `AgentModelName.display` makes it readable.
    var model: String?
    var lastActivity: Date
}

struct UsageRangeSummary: Equatable, Sendable {
    let range: UsageRange
    var byProvider: [UsageProvider: UsageTally] = [:]
    /// Highest spend first.
    var byProject: [UsageBreakdownItem] = []
    var byModel: [UsageBreakdownItem] = []
    var trend: [UsageTrendBar] = []

    var total: UsageTally { byProvider.values.reduce(UsageTally(), +) }

    /// Share of everything the models read that came out of the prompt cache.
    var cacheShare: Double? {
        let tokens = total.tokens
        guard tokens.prompt > 0 else { return nil }
        return Double(tokens.cacheRead) / Double(tokens.prompt)
    }

    /// True when some usage could not be priced, so the figure is a minimum.
    var isLowerBound: Bool { total.unpricedTokens > 0 }
}

struct ProviderStatus: Equatable, Sendable {
    var limits: ProviderLimits?
    /// The plan's marketing name, when a source states it ("Plus", "Pro").
    var plan: String?
    /// The model of the newest request, as a raw ID.
    var model: String?
    /// The newest request in this provider's logs.
    var lastActivity: Date?
    /// Whether any log for this provider exists at all, so a card can say
    /// "nothing yet" rather than vanish for someone who simply has not used it.
    var hasLogs = false
}

/// Everything the Agents tab draws, computed off the main thread in one go.
struct AgentUsageSnapshot: Equatable, Sendable {
    var providers: [UsageProvider: ProviderStatus] = [:]
    var summaries: [UsageRange: UsageRangeSummary] = [:]
    /// Most recently active first.
    var sessions: [AgentSession] = []
    /// When the logs were last read; nil before the first scan finishes.
    var scannedAt: Date?

    static let empty = AgentUsageSnapshot()

    func status(for provider: UsageProvider) -> ProviderStatus {
        providers[provider] ?? ProviderStatus()
    }

    /// The provider's most recent session, if it was active within `window`.
    func latestSession(for provider: UsageProvider, within window: TimeInterval, now: Date = Date()) -> AgentSession? {
        sessions.first { $0.provider == provider && now.timeIntervalSince($0.lastActivity) < window }
    }

    func summary(for range: UsageRange) -> UsageRangeSummary {
        summaries[range] ?? UsageRangeSummary(range: range)
    }

    /// Providers worth a card: anything with logs or a limits reading.
    var visibleProviders: [UsageProvider] {
        UsageProvider.allCases.filter {
            let status = self.status(for: $0)
            return status.hasLogs || status.limits != nil
        }
    }
}

// MARK: - Names

enum AgentModelName {

    /// A model ID as people say it: `claude-sonnet-4-5-20250929` is
    /// "Sonnet 4.5", `gpt-5.1-codex-max` is "GPT-5.1 Codex Max". Anything that
    /// does not follow either family's pattern is shown as it was logged.
    static func display(_ raw: String) -> String {
        let id = AgentPricing.normalized(raw)
        if id.hasPrefix("claude-") {
            let parts = id.dropFirst("claude-".count).split(separator: "-").map(String.init)
            guard let familyIndex = parts.firstIndex(where: { $0.first?.isLetter == true }) else { return raw }
            let family = parts[familyIndex].prefix(1).uppercased() + parts[familyIndex].dropFirst()
            // Newer IDs put the version after the family (opus-4-5), older
            // ones before it (3-5-sonnet).
            let version = (familyIndex == 0 ? parts.dropFirst() : parts.prefix(familyIndex))
                .filter { $0.allSatisfy(\.isNumber) }
                .joined(separator: ".")
            return version.isEmpty ? family : "\(family) \(version)"
        }
        if id.hasPrefix("gpt-") {
            let parts = id.dropFirst("gpt-".count).split(separator: "-").map(String.init)
            // An alias such as `gpt-reserve` has no version to lead with, and
            // is clearer left exactly as Codex logged it.
            guard let version = parts.first, version.first?.isNumber == true else { return raw }
            let rest = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return (["GPT-\(version)"] + rest).joined(separator: " ")
        }
        return raw
    }
}

enum AgentProjectName {

    /// The project an agent ran in, from its working directory.
    ///
    /// Worktrees are named for the repository rather than the worktree:
    /// `~/code/app/.claude/worktrees/fix-login` is the `app` project, which is
    /// how anyone would describe where that work went.
    static func name(fromPath raw: String) -> String? {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/") else { return nil }
        for marker in ["/.claude/worktrees/", "/.codex/worktrees/", "/.worktrees/"] {
            if let range = path.range(of: marker) { path = String(path[..<range.lowerBound]) }
        }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path == NSHomeDirectory() { return "~" }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}

// MARK: - Formatting

extension Int {
    /// `950`, `12.4K`, `3.1M`, `1.2B` — compact enough for a chart caption.
    var compactTokenString: String {
        let value = Double(self)
        switch abs(value) {
        case 1_000_000_000...: return Self.trimmed(value / 1_000_000_000) + "B"
        case 1_000_000...: return Self.trimmed(value / 1_000_000) + "M"
        case 1_000...: return Self.trimmed(value / 1_000) + "K"
        default: return "\(self)"
        }
    }

    private static func trimmed(_ value: Double) -> String {
        // One decimal below 10 ("3.1M"), none above ("50M"), so the caption
        // keeps a steady width as the number grows.
        value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }
}

extension Double {
    /// US dollars, whole cents. Spend is quoted at USD list prices, so it is
    /// not localized into a currency it was never priced in.
    var usdString: String {
        String(format: "$%.2f", self)
    }
}

extension Date {
    /// "now", "4 min ago", "2 hr ago", "3 days ago".
    func shortRelativeString(from now: Date = Date()) -> String {
        let seconds = max(now.timeIntervalSince(self), 0)
        switch seconds {
        case ..<60: return "now"
        case ..<3_600: return "\(Int(seconds / 60)) min ago"
        case ..<86_400: return "\(Int(seconds / 3_600)) hr ago"
        default:
            let days = Int(seconds / 86_400)
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }
}

extension TimeInterval {
    /// "3d 19h", "4h 12m", "38m" — a countdown to a limit renewing.
    var countdownString: String {
        let total = Int(max(self, 0) / 60)
        let days = total / 1_440
        let hours = (total % 1_440) / 60
        let minutes = total % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }
}
