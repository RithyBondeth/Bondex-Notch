import Foundation
import IOKit

struct DeviceBattery: Identifiable, Equatable {
    enum Kind: Equatable {
        case headphones
        case keyboard
        case mouse
        case trackpad
        case generic

        var systemImage: String {
            switch self {
            case .headphones: return "headphones"
            case .keyboard: return "keyboard"
            case .mouse: return "computermouse"
            case .trackpad: return "rectangle.and.hand.point.up.left"
            case .generic: return "battery.75percent"
            }
        }
    }

    let id: String
    let name: String
    let level: Double
    let isCharging: Bool
    let kind: Kind

    var clampedLevel: Double { min(max(level, 0), 1) }
    var percentage: Int { Int((clampedLevel * 100).rounded()) }
    var isLow: Bool { clampedLevel <= 0.2 && !isCharging }
}

/// Reads battery levels that connected HID accessories publish to IORegistry.
/// This does not pair with devices, open Bluetooth connections, or require a
/// privacy permission. Devices that do not publish a level are simply omitted.
@MainActor
final class DeviceBatteryService: ObservableObject {
    @Published private(set) var devices: [DeviceBattery] = []

    typealias BatteryReader = () -> [DeviceBattery]

    private let readBatteries: BatteryReader
    private var timer: Timer?

    init(readBatteries: @escaping BatteryReader = DeviceBatteryService.readAccessories) {
        self.readBatteries = readBatteries
    }

    func start(interval: TimeInterval = 30) {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            onMainActor { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        devices = []
    }

    func refresh() {
        let next = readBatteries()
        if next != devices { devices = next }
    }

    func seedForPreview(_ devices: [DeviceBattery]) {
        self.devices = devices
    }

    // MARK: IORegistry

    nonisolated private static func readAccessories() -> [DeviceBattery] {
        let serviceClasses = [
            "AppleDeviceManagementHIDEventService",
            "AppleBluetoothHIDKeyboard",
            "BNBMouseDevice"
        ]
        var found: [String: DeviceBattery] = [:]

        for serviceClass in serviceClasses {
            guard let matching = IOServiceMatching(serviceClass) else { continue }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(
                kIOMainPortDefault, matching, &iterator
            ) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                guard let properties = properties(of: service),
                      let battery = battery(from: properties)
                else { continue }
                found[battery.id] = battery
            }
        }

        return found.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    nonisolated private static func properties(
        of service: io_registry_entry_t
    ) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service, &properties, kCFAllocatorDefault, 0
        ) == KERN_SUCCESS else { return nil }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    nonisolated static func battery(from properties: [String: Any]) -> DeviceBattery? {
        if value(for: ["Built-In", "BuiltIn"], in: properties) as? Bool == true {
            return nil
        }

        guard let rawLevel = integer(
            for: ["BatteryPercent", "BatteryPercentSingle"],
            in: properties
        ), (0...100).contains(rawLevel) else { return nil }

        let rawName = string(
            for: ["Product", "ProductName", "DeviceName"], in: properties
        ) ?? "Accessory"
        let name = cleanedName(rawName)
        let identity = string(
            for: ["SerialNumber", "DeviceAddress", "BluetoothAddress"],
            in: properties
        ) ?? name
        let chargingValue = value(
            for: ["IsCharging", "BatteryCharging", "DeviceBatteryCharging"],
            in: properties
        )
        let status = string(for: ["BatteryStatus"], in: properties)?.lowercased()
        let isCharging = (chargingValue as? Bool) == true || status == "charging"

        return DeviceBattery(
            id: identity,
            name: name,
            level: Double(rawLevel) / 100,
            isCharging: isCharging,
            kind: kind(for: name)
        )
    }

    nonisolated private static func value(
        for keys: [String], in properties: [String: Any]
    ) -> Any? {
        keys.lazy.compactMap { properties[$0] }.first
    }

    nonisolated private static func integer(
        for keys: [String], in properties: [String: Any]
    ) -> Int? {
        guard let value = value(for: keys, in: properties) else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    nonisolated private static func string(
        for keys: [String], in properties: [String: Any]
    ) -> String? {
        value(for: keys, in: properties) as? String
    }

    nonisolated private static func cleanedName(_ name: String) -> String {
        name.replacingOccurrences(of: "Apple ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func kind(for name: String) -> DeviceBattery.Kind {
        let name = name.lowercased()
        if name.contains("airpod") || name.contains("headphone")
            || name.contains("headset") || name.contains("beats") {
            return .headphones
        }
        if name.contains("keyboard") { return .keyboard }
        if name.contains("trackpad") { return .trackpad }
        if name.contains("mouse") { return .mouse }
        return .generic
    }
}
