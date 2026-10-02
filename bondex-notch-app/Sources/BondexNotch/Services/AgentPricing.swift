import Foundation

/// Public API list prices, for turning token counts into "what this would have
/// cost on the API".
///
/// Subscription plans are not billed per token, so for most people this is a
/// measure of value rather than a bill. It is shown as such ("API value"), and
/// it stays on device: there is no remote price list, because fetching one
/// would be the only network request this feature made.
///
/// Prices are US dollars per million tokens. Sources, checked 2026-10-02:
/// Anthropic's and OpenAI's published API pricing pages. Long-context
/// surcharges and regional multipliers are not modelled, so heavy long-context
/// use is slightly understated.
enum AgentPricing {

    struct Rates: Equatable, Sendable {
        let input: Double
        let output: Double
        /// Five-minute cache writes. OpenAI does not bill writes separately.
        let cacheWrite: Double
        /// One-hour cache writes, which Anthropic bills at twice the input
        /// rate. Claude Code uses them for long sessions.
        let cacheWriteLong: Double
        let cacheRead: Double
        /// Fast mode bills the same tokens at a premium.
        var fastMultiplier: Double = 1

        static func anthropic(
            _ input: Double, _ output: Double, cacheRead: Double, fast: Double = 1
        ) -> Rates {
            Rates(
                input: input,
                output: output,
                cacheWrite: input * 1.25,
                cacheWriteLong: input * 2,
                cacheRead: cacheRead,
                fastMultiplier: fast
            )
        }

        static func openAI(_ input: Double, _ output: Double, cacheRead: Double) -> Rates {
            Rates(input: input, output: output, cacheWrite: input, cacheWriteLong: input, cacheRead: cacheRead)
        }
    }

    /// Exact model IDs, without date stamps. Matching is exact on purpose: a
    /// prefix match would price an unreleased `claude-opus-4-9` as `claude-opus-4`
    /// at three times the real rate, while an unknown model counted as unpriced
    /// only turns the total into a stated lower bound.
    static let table: [String: Rates] = [
        // Anthropic
        "claude-fable-5-1": .anthropic(10, 50, cacheRead: 0.25),
        "claude-mythos-5-1": .anthropic(10, 50, cacheRead: 0.25),
        "claude-fable-5": .anthropic(10, 50, cacheRead: 1),
        "claude-mythos-5": .anthropic(10, 50, cacheRead: 1),
        "claude-mythos-preview": .anthropic(25, 125, cacheRead: 2.5),
        "claude-opus-5-5": .anthropic(4, 20, cacheRead: 0.2, fast: 2),
        "claude-opus-5": .anthropic(5, 25, cacheRead: 0.5, fast: 2),
        "claude-opus-4-8": .anthropic(5, 25, cacheRead: 0.5, fast: 2),
        "claude-opus-4-7": .anthropic(5, 25, cacheRead: 0.5),
        "claude-opus-4-6": .anthropic(5, 25, cacheRead: 0.5),
        "claude-opus-4-5": .anthropic(5, 25, cacheRead: 0.5),
        "claude-opus-4-1": .anthropic(15, 75, cacheRead: 1.5),
        "claude-opus-4": .anthropic(15, 75, cacheRead: 1.5),
        "claude-sonnet-5-5": .anthropic(2, 10, cacheRead: 0.2),
        "claude-sonnet-5": .anthropic(2, 10, cacheRead: 0.2),
        "claude-sonnet-4-6": .anthropic(3, 15, cacheRead: 0.3),
        "claude-sonnet-4-5": .anthropic(3, 15, cacheRead: 0.3),
        "claude-sonnet-4": .anthropic(3, 15, cacheRead: 0.3),
        "claude-3-7-sonnet": .anthropic(3, 15, cacheRead: 0.3),
        "claude-3-5-sonnet": .anthropic(3, 15, cacheRead: 0.3),
        "claude-haiku-4-5": .anthropic(1, 5, cacheRead: 0.1),
        "claude-3-5-haiku": .anthropic(0.8, 4, cacheRead: 0.08),
        "claude-3-opus": .anthropic(15, 75, cacheRead: 1.5),
        "claude-3-haiku": .anthropic(0.25, 1.25, cacheRead: 0.03),

        // OpenAI models Codex runs
        "gpt-6-astra": .openAI(10, 50, cacheRead: 1),
        "gpt-6.1-sol": .openAI(2, 10, cacheRead: 0.1),
        "gpt-6-sol": .openAI(2, 10, cacheRead: 0.2),
        "gpt-6-luna": .openAI(0.1, 0.5, cacheRead: 0.01),
        "gpt-5.6-sol": .openAI(4, 20, cacheRead: 0.4),
        "gpt-5.6-terra": .openAI(2, 12, cacheRead: 0.2),
        "gpt-5.6-luna": .openAI(0.2, 1.2, cacheRead: 0.02),
        "gpt-5.6-cyber": .openAI(12.5, 75, cacheRead: 1.25),
        "gpt-5.5": .openAI(5, 30, cacheRead: 0.5),
        "gpt-5.5-pro": .openAI(30, 180, cacheRead: 30),
        "gpt-5.4": .openAI(2.5, 15, cacheRead: 0.25),
        "gpt-5.4-mini": .openAI(0.75, 4.5, cacheRead: 0.075),
        "gpt-5.4-nano": .openAI(0.2, 1.25, cacheRead: 0.02),
        "gpt-5.3-codex": .openAI(1.75, 14, cacheRead: 0.175),
        "gpt-5.2": .openAI(1.75, 14, cacheRead: 0.175),
        "gpt-5.2-codex": .openAI(1.75, 14, cacheRead: 0.175),
        "gpt-5.1-codex-max": .openAI(1.25, 10, cacheRead: 0.125),
        "gpt-5.1-codex-mini": .openAI(0.25, 2, cacheRead: 0.025),
        "gpt-5.1-codex": .openAI(1.25, 10, cacheRead: 0.125),
        "gpt-5.1": .openAI(1.25, 10, cacheRead: 0.125),
        "gpt-5-codex": .openAI(1.25, 10, cacheRead: 0.125),
        "gpt-5": .openAI(1.25, 10, cacheRead: 0.125),
        "gpt-5-mini": .openAI(0.25, 2, cacheRead: 0.025),
        "gpt-5-nano": .openAI(0.05, 0.4, cacheRead: 0.005),
        "codex-mini-latest": .openAI(1.5, 6, cacheRead: 0.375),
        "o3": .openAI(2, 8, cacheRead: 0.5),
        "o4-mini": .openAI(1.1, 4.4, cacheRead: 0.275),
        "gpt-4.1": .openAI(2, 8, cacheRead: 0.5)
    ]

    /// Anthropic's server-side web search, per request.
    static let webSearchPerRequest = 0.01
    /// Requests pinned to US-only inference are billed at a premium.
    static let usOnlyMultiplier = 1.1

    static func rates(for model: String) -> Rates? {
        table[normalized(model)]
    }

    /// The table's spelling of a model ID as it appears in a log.
    ///
    /// Strips what varies without changing the price: a cloud provider prefix
    /// (`us.anthropic.`), a context-size tag (`[1m]`), a date stamp in either
    /// the first-party (`-20250929`) or Vertex (`@20250929`) form, and a
    /// Bedrock version suffix (`-v1:0`).
    static func normalized(_ model: String) -> String {
        var id = model.lowercased().trimmingCharacters(in: .whitespaces)
        if let bracket = id.firstIndex(of: "[") { id = String(id[..<bracket]) }
        if let slash = id.lastIndex(of: "/") { id = String(id[id.index(after: slash)...]) }
        if let range = id.range(of: "anthropic.") { id = String(id[range.upperBound...]) }
        if let at = id.firstIndex(of: "@") { id = String(id[..<at]) }
        if let range = id.range(of: #"-v\d+(:\d+)?$"#, options: .regularExpression) {
            id.removeSubrange(range)
        }
        if let range = id.range(of: #"-\d{8}$"#, options: .regularExpression) {
            id.removeSubrange(range)
        }
        return id
    }

    /// API-equivalent cost of one request, or nil for a model with no price.
    ///
    /// - Parameter longCacheWrite: the part of `tokens.cacheWrite` written to
    ///   the one-hour cache, which is billed higher than the default.
    static func cost(
        model: String,
        tokens: TokenTally,
        longCacheWrite: Int = 0,
        fast: Bool = false
    ) -> Double? {
        guard let rates = rates(for: model) else { return nil }
        let long = min(max(longCacheWrite, 0), tokens.cacheWrite)
        let dollars = Double(tokens.input) * rates.input
            + Double(tokens.output) * rates.output
            + Double(tokens.cacheWrite - long) * rates.cacheWrite
            + Double(long) * rates.cacheWriteLong
            + Double(tokens.cacheRead) * rates.cacheRead
        return dollars / 1_000_000 * (fast ? rates.fastMultiplier : 1)
    }
}
