import Foundation

/// `--agent-usage-report`: prints what the Agents tab would show, as text.
///
/// The same scan the tab runs, without the panel, so a figure that looks wrong
/// on screen can be checked from a terminal — against the agent's own usage
/// command, or a hand count — without reproducing it under the notch. Prints
/// totals only; no prompt or file content is ever read into it.
enum AgentUsageReport {

    static func run() -> Int32 {
        let started = Date()
        let snapshot = AgentUsageScanner(roots: .standard()).scanNow()
        let elapsed = Date().timeIntervalSince(started)
        print(render(snapshot))
        print(String(format: "scanned in %.2fs", elapsed))
        return 0
    }

    static func render(_ snapshot: AgentUsageSnapshot, now: Date = Date()) -> String {
        var lines: [String] = []
        for provider in UsageProvider.allCases {
            let status = snapshot.status(for: provider)
            var header = "\(provider.displayName):"
            header += status.hasLogs ? " logs found" : " no logs"
            if let plan = status.plan { header += " · plan \(plan)" }
            if let model = status.model { header += " · model \(AgentModelName.display(model))" }
            if let last = status.lastActivity { header += " · last active \(last.shortRelativeString(from: now))" }
            lines.append(header)
            for window in status.limits?.windows ?? [] {
                var line = "  \(window.label): \(String(format: "%.1f", window.usedPercent))%"
                if let resetsAt = window.resetsAt {
                    line += " · renews in \(resetsAt.timeIntervalSince(now).countdownString)"
                }
                lines.append(line)
            }
            if let observed = status.limits?.observedAt {
                lines.append("  limits read \(observed.shortRelativeString(from: now))")
            }
        }

        for range in UsageRange.allCases {
            let summary = snapshot.summary(for: range)
            lines.append("")
            lines.append("\(range.title):")
            for provider in UsageProvider.allCases {
                guard let tally = summary.byProvider[provider] else { continue }
                lines.append("  \(provider.displayName): " + describe(tally))
            }
            lines.append("  Total: " + describe(summary.total)
                + (summary.cacheShare.map { String(format: " · %.0f%% from cache", $0 * 100) } ?? ""))
            for item in summary.byProject.prefix(5) {
                lines.append("    project \(item.name): " + describe(item.tally))
            }
            for item in summary.byModel.prefix(5) {
                lines.append("    model \(item.name): " + describe(item.tally))
            }
        }

        lines.append("")
        lines.append("Recent sessions:")
        for session in snapshot.sessions.prefix(5) {
            lines.append("  \(session.provider.displayName) · \(session.project ?? "?") · "
                + "\(session.model.map(AgentModelName.display) ?? "?") · \(session.lastActivity.shortRelativeString(from: now))")
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ tally: UsageTally) -> String {
        let tokens = tally.tokens
        var text = "\(tokens.total) tokens (in \(tokens.input), out \(tokens.output), "
            + "cache write \(tokens.cacheWrite), cache read \(tokens.cacheRead)) · "
            + String(format: "$%.4f", tally.cost)
        if tally.unpricedTokens > 0 { text += " · \(tally.unpricedTokens) unpriced" }
        return text
    }
}
