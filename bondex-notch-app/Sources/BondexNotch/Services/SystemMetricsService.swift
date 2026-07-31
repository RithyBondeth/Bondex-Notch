import Darwin
import Foundation
import IOKit.ps

struct SystemSnapshot: Equatable {
    var cpuUsage: Double = 0            // 0...1
    var memoryUsed: UInt64 = 0          // bytes
    var memoryTotal: UInt64 = 0
    var memoryPressure: Double = 0      // 0...1
    var batteryLevel: Double?           // 0...1, nil on desktops
    var isCharging = false
    var isPluggedIn = false
    var minutesRemaining: Int?
    var downloadRate: Double = 0        // bytes/sec
    var uploadRate: Double = 0

    var memoryFraction: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal)
    }
}

/// Samples CPU, memory, power and network throughput.
///
/// Sampling runs on a background queue; only the published snapshot crosses
/// back to the main actor.
@MainActor
final class SystemMetricsService: ObservableObject {

    @Published private(set) var snapshot = SystemSnapshot()

    private var timer: Timer?
    private let sampler = MetricsSampler()
    private let events: EventCenter
    private var didWarnLowBattery = false

    init(events: EventCenter) {
        self.events = events
    }

    func start(interval: TimeInterval = 2.0) {
        stop()
        sample()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            onMainActor { self?.sample() }
        }
        // `.common` keeps sampling alive while a menu or drag tracking loop runs.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let sampler = self.sampler
        Task.detached(priority: .utility) {
            let next = sampler.sample()
            await MainActor.run { self.apply(next) }
        }
    }

    private func apply(_ next: SystemSnapshot) {
        snapshot = next
        checkBatteryWarning(next)
    }

    private func checkBatteryWarning(_ next: SystemSnapshot) {
        guard let level = next.batteryLevel else { return }
        if level <= 0.15, !next.isPluggedIn, !didWarnLowBattery {
            didWarnLowBattery = true
            events.post(NotchEvent(
                kind: .system,
                title: "Low Battery",
                subtitle: "\(Int(level * 100))% remaining"
            ))
        } else if level > 0.25 || next.isPluggedIn {
            didWarnLowBattery = false
        }
    }
}

/// The actual sampling. Isolated from the main actor and free of shared mutable
/// state apart from the deltas it needs to compute rates.
private final class MetricsSampler: @unchecked Sendable {

    private let lock = NSLock()
    private var previousCPUTicks: [UInt32] = []
    private var previousNetBytes: (input: UInt64, output: UInt64)?
    private var previousNetSampleAt: Date?

    func sample() -> SystemSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var snapshot = SystemSnapshot()
        snapshot.cpuUsage = readCPUUsage()
        let memory = readMemory()
        snapshot.memoryUsed = memory.used
        snapshot.memoryTotal = memory.total
        snapshot.memoryPressure = memory.pressure
        applyPower(to: &snapshot)
        applyNetwork(to: &snapshot)
        return snapshot
    }

    // MARK: CPU

    /// Aggregate busy fraction across all cores, measured as a delta of the
    /// per-core tick counters between samples.
    private func readCPUUsage() -> Double {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return 0 }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        var ticks: [UInt32] = []
        ticks.reserveCapacity(Int(cpuCount) * Int(CPU_STATE_MAX))
        for index in 0..<Int(cpuCount) * Int(CPU_STATE_MAX) {
            ticks.append(UInt32(bitPattern: info[index]))
        }

        defer { previousCPUTicks = ticks }
        guard previousCPUTicks.count == ticks.count else { return 0 }

        var busy: Double = 0
        var total: Double = 0
        for core in 0..<Int(cpuCount) {
            let base = core * Int(CPU_STATE_MAX)
            let user = delta(ticks, previousCPUTicks, base + Int(CPU_STATE_USER))
            let system = delta(ticks, previousCPUTicks, base + Int(CPU_STATE_SYSTEM))
            let nice = delta(ticks, previousCPUTicks, base + Int(CPU_STATE_NICE))
            let idle = delta(ticks, previousCPUTicks, base + Int(CPU_STATE_IDLE))
            busy += user + system + nice
            total += user + system + nice + idle
        }
        guard total > 0 else { return 0 }
        return min(max(busy / total, 0), 1)
    }

    private func delta(_ current: [UInt32], _ previous: [UInt32], _ index: Int) -> Double {
        Double(current[index] &- previous[index])
    }

    // MARK: Memory

    private func readMemory() -> (used: UInt64, total: UInt64, pressure: Double) {
        let total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total, 0) }

        let pageSize = UInt64(vm_kernel_page_size)
        // Matches how Activity Monitor reports "Memory Used".
        let used = (UInt64(stats.active_count)
                    + UInt64(stats.wire_count)
                    + UInt64(stats.compressor_page_count)) * pageSize

        let pressure = total > 0 ? min(Double(used) / Double(total), 1) : 0
        return (used, total, pressure)
    }

    // MARK: Power

    private func applyPower(to snapshot: inout SystemSnapshot) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 {
                snapshot.batteryLevel = Double(current) / Double(max)
            }
            snapshot.isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            snapshot.isPluggedIn =
                (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            let remaining = snapshot.isPluggedIn
                ? description[kIOPSTimeToFullChargeKey] as? Int
                : description[kIOPSTimeToEmptyKey] as? Int
            // -1 means "still calculating".
            if let remaining, remaining > 0 { snapshot.minutesRemaining = remaining }
            break
        }
    }

    // MARK: Network

    /// Throughput derived from the byte counters of every up, non-loopback
    /// interface.
    private func applyNetwork(to snapshot: inout SystemSnapshot) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return }
        defer { freeifaddrs(addresses) }

        var input: UInt64 = 0
        var output: UInt64 = 0

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0 else { continue }
            guard current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let data = current.pointee.ifa_data?
                .assumingMemoryBound(to: if_data.self) else { continue }

            input += UInt64(data.pointee.ifi_ibytes)
            output += UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        if let previous = previousNetBytes, let previousAt = previousNetSampleAt {
            let elapsed = now.timeIntervalSince(previousAt)
            if elapsed > 0.05 {
                // Counters wrap and interfaces disappear; clamp rather than
                // reporting a nonsense spike.
                snapshot.downloadRate = max(0, Double(input &- previous.input) / elapsed)
                snapshot.uploadRate = max(0, Double(output &- previous.output) / elapsed)
            }
        }
        previousNetBytes = (input, output)
        previousNetSampleAt = now
    }
}
