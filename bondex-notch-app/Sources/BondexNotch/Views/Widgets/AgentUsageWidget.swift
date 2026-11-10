import SwiftUI

/// The Agents tab: plan limits, API-equivalent spend, recent sessions and a
/// breakdown for Claude Code and Codex, read from their local logs.
///
/// Laid out as a small dashboard — two provider cards, spend beside the
/// sessions, then trend, projects or models — and measured from its content
/// like Home, so the panel is exactly as tall as what it shows. Every card has
/// a bounded height (a provider shows at most three limit rows, sessions and
/// breakdowns at most three lines), which keeps the worst case inside the
/// panel's height ceiling.
struct AgentUsageWidget: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var usage: AgentUsageService
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var agents: AgentActivityService

    /// Not persisted: each opening starts on the trend, which is the view that
    /// answers "how much today" at a glance.
    @State private var breakdown: UsageBreakdown = .trend

    /// `breakdown` exists for the preview tool, which renders each view.
    init(environment: AppEnvironment, breakdown: UsageBreakdown = .trend) {
        self.environment = environment
        self.usage = environment.agentUsage
        self.settings = environment.settings
        self.agents = environment.agents
        _breakdown = State(initialValue: breakdown)
    }

    private var snapshot: AgentUsageSnapshot { usage.snapshot }
    private var range: UsageRange { settings.preferences.agentUsageRange }

    var body: some View {
        Group {
            if snapshot.scannedAt == nil {
                loading
            } else if snapshot.visibleProviders.isEmpty {
                EmptyStateView(
                    systemImage: "cpu",
                    title: "No agent usage yet",
                    subtitle: "Claude Code and Codex usage on this Mac appears here. Nothing leaves your device."
                )
            } else {
                dashboard
            }
        }
        .onAppear { usage.refresh(ifOlderThan: 15) }
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading agent logs…")
                .font(.system(size: Theme.TextSize.body, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var dashboard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            let summary = snapshot.summary(for: range)
            VStack(spacing: Theme.widgetSpacing) {
                HStack(alignment: .top, spacing: Theme.widgetSpacing) {
                    ForEach(snapshot.visibleProviders) { provider in
                        ProviderUsageCard(
                            provider: provider,
                            status: snapshot.status(for: provider),
                            today: snapshot.summary(for: .today).byProvider[provider] ?? UsageTally(),
                            now: now
                        )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: Theme.widgetSpacing) {
                    SpendingCard(
                        summary: summary,
                        providers: snapshot.visibleProviders,
                        range: rangeBinding
                    )
                    SessionsCard(
                        rows: sessionRows(now: now),
                        now: now,
                        showsActivityHint: !settings.preferences.agentActivityEnabled,
                        enableActivity: { settings.preferences.agentActivityEnabled = true }
                    )
                }
                .fixedSize(horizontal: false, vertical: true)

                BreakdownCard(
                    summary: summary,
                    providers: snapshot.visibleProviders,
                    breakdown: $breakdown
                )
            }
        }
    }

    private var rangeBinding: Binding<UsageRange> {
        Binding(
            get: { settings.preferences.agentUsageRange },
            set: { settings.preferences.agentUsageRange = $0 }
        )
    }

    /// The latest sessions from the logs, with live status from the agent
    /// hooks laid over the newest session of each working agent. An agent that
    /// reports work but leaves no usage logs Bondex reads — Gemini, say — still
    /// gets a row, because "it is running" is worth showing on its own.
    private func sessionRows(now: Date) -> [SessionsCard.Row] {
        let working = agents.active.filter(\.isHookReported)
        var claimed = Set<AgentKind>()
        var rows: [SessionsCard.Row] = snapshot.sessions.map { session in
            let kind = session.provider.kind
            var live: String?
            // A hook only says *which agent* is working, so it is credited to
            // that agent's most recent session, and only if that session wrote
            // to its log recently enough to plausibly be the one.
            var waiting = false
            if !claimed.contains(kind),
               let agent = working.first(where: { $0.kind == kind }),
               now.timeIntervalSince(session.lastActivity) < 15 * 60 {
                live = agent.status ?? "Working"
                waiting = agent.needsAttention
                claimed.insert(kind)
            }
            return SessionsCard.Row(
                id: session.id,
                kind: kind,
                project: session.project,
                model: session.model.map(AgentModelName.display),
                lastActivity: session.lastActivity,
                liveStatus: live,
                needsAttention: waiting
            )
        }
        rows += working
            .filter { !claimed.contains($0.kind) }
            .map { agent in
                SessionsCard.Row(
                    id: "live:" + agent.kind.id,
                    kind: agent.kind,
                    project: nil,
                    model: nil,
                    lastActivity: nil,
                    liveStatus: agent.status ?? "Working",
                    needsAttention: agent.needsAttention
                )
            }

        let sorted = rows.sorted { lhs, rhs in
            if (lhs.liveStatus != nil) != (rhs.liveStatus != nil) { return lhs.liveStatus != nil }
            return (lhs.lastActivity ?? .distantPast) > (rhs.lastActivity ?? .distantPast)
        }
        return Array(sorted.prefix(settings.preferences.agentActivityEnabled ? 3 : 2))
    }
}

private extension Theme {
    /// The same warm red the System widget uses for a gauge near its limit.
    static let limitWarning = Color(red: 0.98, green: 0.35, blue: 0.35)
}

// MARK: - Card chrome

/// The icon-and-title row every card opens with.
private struct CardHeader<Accessory: View>: View {
    let title: String
    var systemImage: String?
    var kind: AgentKind?
    /// Secondary text after the title, such as the model in use.
    var detail: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 7) {
            if let kind {
                PixelMark(kind: kind)
                    .frame(width: 15, height: 15)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 15)
            }
            Text(title)
                .font(.system(size: Theme.TextSize.title, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .fixedSize()
            if let detail {
                Text(detail)
                    .font(.system(size: Theme.TextSize.body, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            accessory()
        }
        // Fixed, so a card with a plan badge or range chips in its header
        // starts its rows level with the card beside it.
        .frame(height: 19)
    }
}

private extension CardHeader where Accessory == EmptyView {
    init(title: String, systemImage: String? = nil, kind: AgentKind? = nil, detail: String? = nil) {
        self.init(title: title, systemImage: systemImage, kind: kind, detail: detail) { EmptyView() }
    }
}

private extension View {
    /// Card chrome for the dashboard.
    ///
    /// - Parameter fillsRow: stretch to the tallest card beside it, so a row
    ///   of cards ends level. Only for cards inside a row that is itself
    ///   `fixedSize`d: anywhere else, unlimited height would claim every point
    ///   the panel offers and pin it at its height ceiling.
    func dashboardCard(fillsRow: Bool = true) -> some View {
        frame(maxWidth: .infinity, maxHeight: fillsRow ? .infinity : nil, alignment: .topLeading)
            .notchCard(padding: 10)
    }
}

/// Small segmented chips for switching a card's view.
private struct ChipPicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var fontSize: CGFloat = 9.5

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(selection == option ? Theme.primaryText : Theme.tertiaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule().fill(selection == option ? Color.white.opacity(0.14) : .clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(1.5)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Provider

private struct ProviderUsageCard: View {
    let provider: UsageProvider
    let status: ProviderStatus
    let today: UsageTally
    let now: Date

    /// More than this and the row would push the dashboard past the panel.
    private static let maximumWindows = 3
    /// A reading older than this is labelled with its age.
    private static let freshness: TimeInterval = 15 * 60

    private var tint: Color { provider.kind.tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(
                title: provider.displayName,
                kind: provider.kind,
                detail: status.model.map(AgentModelName.display)
            ) {
                if let plan = status.plan {
                    Text(plan)
                        .font(.system(size: Theme.TextSize.footnote, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(tint.opacity(0.17)))
                        .fixedSize()
                }
            }

            if let limits = status.limits, !limits.windows.isEmpty {
                ForEach(limits.windows.prefix(Self.maximumWindows)) { window in
                    LimitRow(window: window, tint: tint, now: now)
                }
                if now.timeIntervalSince(limits.observedAt) > Self.freshness {
                    Text("Updated \(limits.observedAt.shortRelativeString(from: now))")
                        .font(.system(size: Theme.TextSize.footnote))
                        .foregroundStyle(Theme.tertiaryText)
                }
            } else {
                noLimits
            }
        }
        .dashboardCard()
        .accessibilityElement(children: .combine)
    }

    /// Without an allowance reading the card still says something true —
    /// today's volume — and where limits would come from.
    private var noLimits: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(today.tokens.total.compactTokenString)
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
                Text("tokens today")
                    .font(.system(size: Theme.TextSize.footnote))
                    .foregroundStyle(Theme.tertiaryText)
            }
            Text(limitsHint)
                .font(.system(size: Theme.TextSize.footnote))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var limitsHint: String {
        switch provider {
        case .claude: return "Plan limits appear while the Claude app is running."
        case .codex: return "Plan limits appear after your next Codex turn."
        }
    }
}

private struct LimitRow: View {
    let window: UsageLimitWindow
    let tint: Color
    let now: Date

    private var isNearLimit: Bool { window.usedPercent >= 90 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(window.label)
                    .font(.system(size: Theme.TextSize.body, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if let resetsAt = window.resetsAt {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8, weight: .semibold))
                        Text(resetsAt.timeIntervalSince(now).countdownString)
                            .font(.system(size: Theme.TextSize.footnote).monospacedDigit())
                    }
                    .foregroundStyle(Theme.tertiaryText)
                    .help("Renews \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
                }
                Spacer(minLength: 4)
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: Theme.TextSize.title, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isNearLimit ? Theme.limitWarning : Theme.primaryText)
            }
            LimitBar(
                value: window.fraction,
                pace: window.elapsedFraction(at: now),
                tint: isNearLimit ? Theme.limitWarning : tint
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.label) limit")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var value = "\(Int(window.usedPercent.rounded())) percent used"
        if let resetsAt = window.resetsAt {
            value += ", renews in \(resetsAt.timeIntervalSince(now).countdownString)"
        }
        return value
    }
}

/// A usage bar with a tick for how far through its window the clock is: fill
/// past the tick means the allowance is being spent faster than it renews.
private struct LimitBar: View {
    let value: Double
    let pace: Double?
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.11))
                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.width * value, value > 0 ? 5 : 0))
                if let pace {
                    RoundedRectangle(cornerRadius: 0.75)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 1.5, height: proxy.size.height + 4)
                        .offset(x: min(max(proxy.size.width * pace - 0.75, 0), proxy.size.width - 1.5))
                }
            }
        }
        .frame(height: 6)
        .padding(.vertical, 2)
    }
}

// MARK: - Spending

private struct SpendingCard: View {
    let summary: UsageRangeSummary
    let providers: [UsageProvider]
    @Binding var range: UsageRange

    var body: some View {
        let total = summary.total
        VStack(alignment: .leading, spacing: 7) {
            CardHeader(title: "Spending", systemImage: "dollarsign.circle") {
                ChipPicker(options: UsageRange.allCases, selection: $range, title: \.shortTitle)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text((summary.isLowerBound ? "≥ " : "") + total.cost.usdString)
                    .font(.system(size: 25, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("API value")
                    .font(.system(size: Theme.TextSize.footnote))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize()
            }
            .help(spendHelp)

            ShareBar(segments: providers.map { provider in
                let tally = summary.byProvider[provider] ?? UsageTally()
                // Tokens stand in when nothing could be priced, so the bar
                // still shows who did the work.
                return (provider.kind.tint, total.cost > 0 ? tally.cost : Double(tally.tokens.total))
            })

            // Which colour is which, and what each came to.
            HStack(spacing: 10) {
                ForEach(providers) { provider in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(provider.kind.tint)
                            .frame(width: 6, height: 6)
                        Text(provider.displayName)
                            .font(.system(size: Theme.TextSize.footnote))
                            .foregroundStyle(Theme.secondaryText)
                        Text((summary.byProvider[provider]?.cost ?? 0).usdString)
                            .font(.system(size: Theme.TextSize.footnote, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.primaryText)
                    }
                    .fixedSize()
                }
            }

            Text(detail)
                .font(.system(size: Theme.TextSize.footnote))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
        }
        .dashboardCard()
    }

    private var detail: String {
        var parts = ["\(summary.total.tokens.total.compactTokenString) tokens"]
        if let share = summary.cacheShare {
            parts.append("\(Int((share * 100).rounded()))% from cache")
        }
        return parts.joined(separator: " · ")
    }

    private var spendHelp: String {
        var text = "What these tokens would cost at public API list prices. Subscription plans are not billed per token."
        if summary.isLowerBound {
            text += " Some usage came from a model without a known price, so this is a minimum."
        }
        return text
    }
}

private extension UsageRange {
    var shortTitle: String {
        switch self {
        case .today: return "1D"
        case .week: return "7D"
        case .month: return "30D"
        }
    }
}

/// Proportions of a whole, as adjoining capsules.
private struct ShareBar: View {
    let segments: [(color: Color, value: Double)]

    var body: some View {
        let visible = segments.filter { $0.value > 0 }
        let total = visible.reduce(0) { $0 + $1.value }
        GeometryReader { proxy in
            HStack(spacing: 3) {
                if visible.isEmpty {
                    Capsule().fill(Color.white.opacity(0.11))
                } else {
                    let gaps = CGFloat(visible.count - 1) * 3
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, segment in
                        Capsule()
                            .fill(segment.color)
                            .frame(width: max((proxy.size.width - gaps) * segment.value / total, 4))
                    }
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

// MARK: - Sessions

private struct SessionsCard: View {
    struct Row: Identifiable, Equatable {
        let id: String
        let kind: AgentKind
        let project: String?
        /// Already readable, e.g. "Sonnet 5.5".
        let model: String?
        let lastActivity: Date?
        /// What a hook says the agent is doing right now, if it is working.
        let liveStatus: String?
        /// The agent is stopped, waiting on the user.
        var needsAttention = false
    }

    let rows: [Row]
    let now: Date
    /// Agent activity is what reports live work; without it every session
    /// reads as idle, so the card says how to turn it on.
    let showsActivityHint: Bool
    let enableActivity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Sessions", systemImage: "waveform.path.ecg")

            if rows.isEmpty {
                Text("No recent sessions")
                    .font(.system(size: Theme.TextSize.body))
                    .foregroundStyle(Theme.tertiaryText)
            }
            ForEach(rows) { row in
                SessionRow(row: row, now: now)
            }
            if showsActivityHint {
                Button(action: enableActivity) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8.5, weight: .semibold))
                        Text("Show live work in the notch")
                            .font(.system(size: Theme.TextSize.footnote, weight: .medium))
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Turns on Agent activity, which shows agents working beside the notch.")
            }
        }
        .dashboardCard()
    }
}

private struct SessionRow: View {
    let row: SessionsCard.Row
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if row.liveStatus != nil {
                    // The same mark the peek shows, spinning while the agent
                    // works, so a running session reads as running here too.
                    AgentOrb(kind: row.kind, size: 20, needsAttention: row.needsAttention)
                } else {
                    PixelMark(kind: row.kind)
                        .frame(width: 13, height: 13)
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.project ?? row.kind.displayName)
                    .font(.system(size: Theme.TextSize.title, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let status = row.liveStatus {
                    Text(status)
                        .font(.system(size: Theme.TextSize.footnote, weight: .medium))
                        .foregroundStyle(row.needsAttention ? Theme.attention : row.kind.tint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let model = row.model {
                    Text(model)
                        .font(.system(size: Theme.TextSize.footnote))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Group {
                if row.needsAttention {
                    Text("Needs you")
                        .foregroundStyle(Theme.attention)
                } else if row.liveStatus != nil {
                    Text(row.model ?? "Working")
                } else if let last = row.lastActivity {
                    Text(last.shortRelativeString(from: now))
                } else {
                    Text("—")
                }
            }
            .font(.system(size: Theme.TextSize.footnote).monospacedDigit())
            .foregroundStyle(Theme.tertiaryText)
            .lineLimit(1)
            .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Breakdown

enum UsageBreakdown: String, CaseIterable, Identifiable {
    case trend
    case projects
    case models

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trend: return "Trend"
        case .projects: return "Projects"
        case .models: return "Models"
        }
    }
}

private struct BreakdownCard: View {
    let summary: UsageRangeSummary
    let providers: [UsageProvider]
    @Binding var breakdown: UsageBreakdown

    /// Every view gets the same height, so switching between them does not
    /// resize the panel under the pointer.
    private static let contentHeight: CGFloat = 64
    private static let chartHeight: CGFloat = 44
    private static let listRows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 15)
                ChipPicker(
                    options: UsageBreakdown.allCases,
                    selection: $breakdown,
                    title: \.title,
                    fontSize: 10.5
                )
                Spacer(minLength: 4)
                Text("\(summary.range.title) · \(summary.total.tokens.total.compactTokenString) tokens")
                    .font(.system(size: Theme.TextSize.footnote).monospacedDigit())
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }
            .frame(height: 19)

            Group {
                switch breakdown {
                case .trend:
                    VStack(spacing: 7) {
                        bars
                        labels
                    }
                case .projects:
                    list(summary.byProject, empty: "No project usage in this range")
                case .models:
                    list(summary.byModel, empty: "No model usage in this range")
                }
            }
            .frame(height: Self.contentHeight, alignment: .top)
        }
        .dashboardCard(fillsRow: false)
    }

    private var icon: String {
        switch breakdown {
        case .trend: return "chart.bar.fill"
        case .projects: return "folder.fill"
        case .models: return "cpu"
        }
    }

    // MARK: Trend

    private var peak: Int { max(summary.trend.map(\.totalTokens).max() ?? 0, 1) }

    private var spacing: CGFloat { summary.trend.count > 12 ? 2.5 : 5 }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(summary.trend) { bar in
                VStack(spacing: 1) {
                    if bar.totalTokens == 0 {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 2)
                    } else {
                        // Stacked with the first provider at the base, so each
                        // colour keeps its place from bar to bar.
                        ForEach(providers.reversed()) { provider in
                            if let tokens = bar.tokens[provider], tokens > 0 {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(provider.kind.tint)
                                    .frame(height: max(Self.chartHeight * CGFloat(tokens) / CGFloat(peak), 2))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: Self.chartHeight, alignment: .bottom)
                .help(help(for: bar))
            }
        }
        .frame(height: Self.chartHeight, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage trend, \(summary.range.title)")
        .accessibilityValue("\(summary.total.tokens.total.compactTokenString) tokens")
    }

    /// One label per few bars, so a 30-bar chart does not turn into a ruler.
    private var labels: some View {
        let step = summary.range == .today ? 6 : (summary.range == .week ? 1 : 5)
        return HStack(spacing: spacing) {
            ForEach(Array(summary.trend.enumerated()), id: \.element.id) { index, bar in
                Text(index % step == 0 ? label(for: bar.start) : "")
                    .font(.system(size: Theme.TextSize.micro).monospacedDigit())
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 10)
    }

    private func label(for date: Date) -> String {
        switch summary.range {
        case .today: return date.formatted(.dateTime.hour(.defaultDigits(amPM: .narrow)))
        case .week: return date.formatted(.dateTime.weekday(.narrow))
        case .month: return date.formatted(.dateTime.day())
        }
    }

    private func help(for bar: UsageTrendBar) -> String {
        let when = summary.range == .today
            ? bar.start.formatted(date: .omitted, time: .shortened)
            : bar.start.formatted(date: .abbreviated, time: .omitted)
        let cost = bar.cost.values.reduce(0, +)
        return "\(when): \(bar.totalTokens.compactTokenString) tokens · \(cost.usdString)"
    }

    // MARK: Lists

    @ViewBuilder
    private func list(_ items: [UsageBreakdownItem], empty: String) -> some View {
        if items.isEmpty {
            Text(empty)
                .font(.system(size: Theme.TextSize.body))
                .foregroundStyle(Theme.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let shown = Array(items.prefix(Self.listRows))
            let others = items.dropFirst(Self.listRows)
            let lead = max(items.first?.tally.cost ?? 0, 0.000_001)
            VStack(spacing: 3) {
                ForEach(shown) { item in
                    BreakdownRow(
                        name: item.name,
                        tint: item.provider.kind.tint,
                        tally: item.tally,
                        share: summary.total.cost > 0 ? item.tally.cost / lead : 0
                    )
                }
                if !others.isEmpty {
                    let rest = others.reduce(UsageTally()) { $0 + $1.tally }
                    Text("+\(others.count) more · \(rest.tokens.total.compactTokenString) tokens · \(rest.cost.usdString)")
                        .font(.system(size: Theme.TextSize.caption))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct BreakdownRow: View {
    let name: String
    let tint: Color
    let tally: UsageTally
    /// Relative to the top row, for the inline bar.
    let share: Double

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: Theme.TextSize.body, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(width: max(proxy.size.width * min(share, 1), share > 0 ? 3 : 0))
                }
            }
            .frame(width: 64, height: 4)
            Text(tally.tokens.total.compactTokenString)
                .font(.system(size: Theme.TextSize.footnote).monospacedDigit())
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 38, alignment: .trailing)
            Text((tally.unpricedTokens > 0 && tally.cost == 0) ? "—" : tally.cost.usdString)
                .font(.system(size: Theme.TextSize.body, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.primaryText)
                .frame(width: 58, alignment: .trailing)
        }
        .frame(height: 14)
        .accessibilityElement(children: .combine)
    }
}
