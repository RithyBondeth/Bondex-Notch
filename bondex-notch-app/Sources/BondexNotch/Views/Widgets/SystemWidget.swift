import SwiftUI

/// CPU, memory, power and throughput. Used standalone and as the bottom half
/// of the Home tab.
struct SystemWidget: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var service: SystemMetricsService
    @ObservedObject private var deviceBatteries: DeviceBatteryService
    @ObservedObject private var settings: SettingsStore

    var compact = false

    init(environment: AppEnvironment, compact: Bool = false) {
        self.environment = environment
        self.service = environment.metrics
        self.deviceBatteries = environment.deviceBatteries
        self.settings = environment.settings
        self.compact = compact
    }

    private var accent: Color { settings.effectiveAccentColor }
    private var snapshot: SystemSnapshot { service.snapshot }

    var body: some View {
        VStack(spacing: 8) {
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

            if !compact {
                deviceBatteryPanel
            }
        }
        .animation(Motion.value(settings.motion), value: batteryDisplays)
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

    // MARK: Device batteries

    private struct BatteryDisplay: Identifiable, Equatable {
        let id: String
        let name: String
        let level: Double
        let isCharging: Bool
        let systemImage: String
    }

    private var batteryDisplays: [BatteryDisplay] {
        var displays: [BatteryDisplay] = []
        if let level = snapshot.batteryLevel {
            displays.append(BatteryDisplay(
                id: "this-mac",
                name: "This Mac",
                level: level,
                isCharging: snapshot.isCharging,
                systemImage: "laptopcomputer"
            ))
        }
        displays.append(contentsOf: deviceBatteries.devices.map {
            BatteryDisplay(
                id: $0.id,
                name: $0.name,
                level: $0.clampedLevel,
                isCharging: $0.isCharging,
                systemImage: $0.kind.systemImage
            )
        })
        return displays
    }

    private var deviceBatteryPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "battery.100percent")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent)
                Text("Device batteries")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                if !batteryDisplays.isEmpty {
                    Text("\(batteryDisplays.count) device\(batteryDisplays.count == 1 ? "" : "s")")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            if batteryDisplays.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "battery.0percent")
                    Text("No battery-powered devices detected")
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(batteryDisplays.prefix(4))) { device in
                        deviceBatteryCell(device)
                    }
                    if batteryDisplays.count > 4 {
                        Text("+\(batteryDisplays.count - 4)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 24)
                            .accessibilityLabel("\(batteryDisplays.count - 4) more devices")
                    }
                }
            }
        }
        .notchCard(padding: 9)
    }

    private func deviceBatteryCell(_ device: BatteryDisplay) -> some View {
        let tint = batteryTint(device.level, charging: device.isCharging)
        return HStack(spacing: 6) {
            ZStack {
                Circle().fill(tint.opacity(0.14))
                Image(systemName: device.isCharging ? "bolt.fill" : device.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 25, height: 25)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("\(Int((device.level * 100).rounded()))%")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.name)
        .accessibilityValue(
            "\(Int((device.level * 100).rounded())) percent"
                + (device.isCharging ? ", charging" : "")
                + (device.level <= 0.2 && !device.isCharging ? ", low battery" : "")
        )
        .help(
            "\(device.name): \(Int((device.level * 100).rounded()))%"
                + (device.isCharging ? " · Charging" : "")
        )
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
        batteryTint(level, charging: snapshot.isCharging)
    }

    private func batteryTint(_ level: Double, charging: Bool) -> Color {
        if charging { return Color(red: 0.32, green: 0.80, blue: 0.55) }
        switch level {
        case ..<0.15: return Color(red: 0.98, green: 0.35, blue: 0.35)
        case ..<0.3: return Color(red: 0.99, green: 0.72, blue: 0.25)
        default: return accent
        }
    }
}
