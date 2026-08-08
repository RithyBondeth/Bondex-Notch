import XCTest
@testable import BondexNotch

@MainActor
final class PrivacyActivityServiceTests: XCTestCase {

    func testRefreshReportsEachDeviceAndCombinedActivity() {
        var microphone = false
        var camera = false
        let service = PrivacyActivityService(
            readMicrophoneActivity: { microphone },
            readCameraActivity: { camera }
        )

        service.refresh()
        XCTAssertEqual(service.state, PrivacyActivityState())

        microphone = true
        service.refresh()
        XCTAssertEqual(
            service.state,
            PrivacyActivityState(microphoneActive: true, cameraActive: false)
        )
        XCTAssertEqual(service.state.label, "Microphone")

        camera = true
        service.refresh()
        XCTAssertEqual(
            service.state,
            PrivacyActivityState(microphoneActive: true, cameraActive: true)
        )
        XCTAssertEqual(service.state.label, "Camera & Microphone")

        microphone = false
        service.refresh()
        XCTAssertEqual(
            service.state,
            PrivacyActivityState(microphoneActive: false, cameraActive: true)
        )
        XCTAssertEqual(service.state.label, "Camera")
    }

    func testStopClearsActivityImmediately() {
        let service = PrivacyActivityService(
            readMicrophoneActivity: { true },
            readCameraActivity: { true }
        )

        service.refresh()
        XCTAssertTrue(service.state.isActive)

        service.stop()
        XCTAssertEqual(service.state, PrivacyActivityState())
        XCTAssertEqual(service.state.accessibilityValue, "Camera and microphone inactive")
    }
}
