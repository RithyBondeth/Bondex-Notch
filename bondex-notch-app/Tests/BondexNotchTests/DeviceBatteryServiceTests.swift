import XCTest
@testable import BondexNotch

@MainActor
final class DeviceBatteryServiceTests: XCTestCase {

    func testRegistryPropertiesBecomeADeviceBattery() throws {
        let battery = try XCTUnwrap(DeviceBatteryService.battery(from: [
            "Product": "Apple Magic Trackpad",
            "SerialNumber": "trackpad-1",
            "BatteryPercent": 18,
            "IsCharging": false
        ]))

        XCTAssertEqual(battery.id, "trackpad-1")
        XCTAssertEqual(battery.name, "Magic Trackpad")
        XCTAssertEqual(battery.level, 0.18, accuracy: 0.0001)
        XCTAssertEqual(battery.kind, .trackpad)
        XCTAssertTrue(battery.isLow)
    }

    func testStringLevelAndChargingStatusAreSupported() throws {
        let battery = try XCTUnwrap(DeviceBatteryService.battery(from: [
            "ProductName": "Studio Headphones",
            "DeviceAddress": "headphones-1",
            "BatteryPercentSingle": "73",
            "BatteryStatus": "Charging"
        ]))

        XCTAssertEqual(battery.percentage, 73)
        XCTAssertEqual(battery.kind, .headphones)
        XCTAssertTrue(battery.isCharging)
        XCTAssertFalse(battery.isLow)
    }

    func testBuiltInAndInvalidEntriesAreIgnored() {
        XCTAssertNil(DeviceBatteryService.battery(from: [
            "Product": "Apple Internal Keyboard / Trackpad",
            "Built-In": true,
            "BatteryPercent": 100
        ]))
        XCTAssertNil(DeviceBatteryService.battery(from: [
            "Product": "Unknown",
            "BatteryPercent": 101
        ]))
        XCTAssertNil(DeviceBatteryService.battery(from: ["Product": "No Battery"]))
    }

    func testRefreshPublishesChangesAndStopClearsThem() {
        var devices: [DeviceBattery] = []
        let service = DeviceBatteryService(readBatteries: { devices })

        service.refresh()
        XCTAssertTrue(service.devices.isEmpty)

        devices = [DeviceBattery(
            id: "mouse-1",
            name: "Magic Mouse",
            level: 0.44,
            isCharging: false,
            kind: .mouse
        )]
        service.refresh()
        XCTAssertEqual(service.devices, devices)

        service.stop()
        XCTAssertTrue(service.devices.isEmpty)
    }
}
