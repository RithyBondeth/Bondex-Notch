import SwiftUI

/// CPU, memory, power and throughput. Used standalone and as the bottom half
/// of the Home tab.
struct SystemWidget: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var service: SystemMetricsService
    @ObservedObject private var settings: SettingsStore

    var compact = false

    init(environment: AppEnvironment, compact: Bool = false) {
        self.environment = environment
        self.service = environment.metrics
        self.settings = environment.settings
        self.compact = compact
    }

    private var accent: Color { settings.effectiveAccentColor }
    private var snapshot: SystemSnapshot { service.snapshot }

    var body: some View {
        HStack(spacing: 8) {
            gauge(
                title: "CPU",
                value: snapshot.cpuUsage,
                tint: tint(for: snapshot.cpuUsage),
                help: "CPU load across all cores"
            )

            gauge(
                title: "Memory",
                value: snapshot.memoryFraction,
                tint: tint(for: snapshot.memoryFraction),
                help: snapshot.memoryTotal > 0
                    ? "\(Int64(snapshot.memoryUsed).formattedBytes) of \(Int64(snapshot.memoryTotal).formattedBytes) used"
                    : "Memory usage unavailable"
            )

            battery

            network
        }
        .animation(Motion.value(settings.motion), value: snapshot)
    }

    // MARK: Tiles

    private func gauge(
        title: String,
        value: Double,
        tint: Color,
        help: String
    ) -> some View {
        VStack(spacing: 5) {
            ZStack {
                ProgressRing(value: value, tint: tint, lineWidth: 3.5)
                Text("\(Int(value * 100))%")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
            }
            .frame(width: compact ? 28 : 38, height: compact ? 28 : 38)

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .notchCard(padding: compact ? Theme.compactCardPadding : 10)
        .help(help)
    }

    private var battery: some View {
        VStack(spacing: 5) {
            ZStack {
                if let level = snapshot.batteryLevel {
                    ProgressRing(value: level, tint: batteryTint(level), lineWidth: 3.5)
                    Image(systemName: snapshot.isCharging ? "bolt.fill" : "battery.100")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(batteryTint(level))
                } else {
                    ProgressRing(value: 1, tint: Theme.tertiaryText, lineWidth: 3.5)
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .frame(width: compact ? 28 : 38, height: compact ? 28 : 38)

            Text(batteryCaption)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .notchCard(padding: compact ? Theme.compactCardPadding : 10)
        .help(batteryHelp)
    }

    private var batteryHelp: String {
        guard snapshot.batteryLevel != nil else { return "Running on AC power" }
        if snapshot.isCharging { return "Charging" }
        if let minutes = snapshot.minutesRemaining {
            return "About \(minutes / 60)h \(minutes % 60)m remaining"
        }
        return "On battery"
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 6) {
            throughput(
                systemImage: "arrow.down",
                rate: snapshot.downloadRate,
                tint: accent
            )
            throughput(
                systemImage: "arrow.up",
                rate: snapshot.uploadRate,
                tint: Theme.secondaryText
            )
            Text("Network")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard(padding: compact ? Theme.compactCardPadding : 10)
    }

    private func throughput(systemImage: String, rate: Double, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
            Text(rateString(rate))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    // MARK: Formatting

    private var batteryCaption: String {
        guard let level = snapshot.batteryLevel else { return "AC Power" }
        if let minutes = snapshot.minutesRemaining, !snapshot.isCharging {
            return "\(Int(level * 100))% · \(minutes / 60)h \(minutes % 60)m"
        }
        return "\(Int(level * 100))%"
    }

    private func rateString(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond >= 1024 else { return "0 KB/s" }
        return "\(Int64(bytesPerSecond).formattedBytes)/s"
    }

    /// Green through amber to red as load climbs, so a glance is enough.
    private func tint(for value: Double) -> Color {
        switch value {
        case ..<0.6: return accent
        case ..<0.85: return Color(red: 0.99, green: 0.72, blue: 0.25)
        default: return Color(red: 0.98, green: 0.35, blue: 0.35)
        }
    }

    private func batteryTint(_ level: Double) -> Color {
        if snapshot.isCharging { return Color(red: 0.32, green: 0.80, blue: 0.55) }
        switch level {
        case ..<0.15: return Color(red: 0.98, green: 0.35, blue: 0.35)
        case ..<0.3: return Color(red: 0.99, green: 0.72, blue: 0.25)
        default: return accent
        }
    }
}
