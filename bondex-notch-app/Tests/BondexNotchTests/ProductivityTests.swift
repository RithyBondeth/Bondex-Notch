import Foundation
import EventKit
import XCTest
@testable import BondexNotch

@MainActor
final class FocusTimerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.bondex.notch.tests.focus.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStartPauseResumeAndCancel() {
        let timer = FocusTimerService(defaults: defaults, events: EventCenter())

        timer.start(minutes: 25)
        XCTAssertTrue(timer.snapshot.isRunning)
        XCTAssertEqual(timer.snapshot.duration, 25 * 60, accuracy: 0.01)

        timer.pause()
        XCTAssertEqual(timer.snapshot.phase, .paused)
        XCTAssertGreaterThan(timer.snapshot.remaining, 0)

        timer.resume()
        XCTAssertTrue(timer.snapshot.isRunning)

        timer.cancel()
        XCTAssertEqual(timer.snapshot.phase, .idle)
        XCTAssertFalse(timer.snapshot.isActive)
    }

    func testDurationIsClampedToSafeBounds() {
        let timer = FocusTimerService(defaults: defaults, events: EventCenter())
        timer.start(minutes: 0)
        XCTAssertEqual(timer.snapshot.duration, 60, accuracy: 0.01)

        timer.start(minutes: 999)
        XCTAssertEqual(timer.snapshot.duration, 180 * 60, accuracy: 0.01)
        timer.cancel()
    }

    func testPausedTimerRestoresAfterRestart() {
        let original = FocusTimerService(defaults: defaults, events: EventCenter())
        original.start(minutes: 25)
        original.pause()

        let restored = FocusTimerService(defaults: defaults, events: EventCenter())
        XCTAssertEqual(restored.snapshot.phase, .paused)
        XCTAssertEqual(restored.snapshot.duration, 25 * 60, accuracy: 0.01)
        XCTAssertGreaterThan(restored.snapshot.remaining, 0)

        restored.cancel()
    }

    func testRunningTimerRestoresFromItsEndDate() {
        defaults.set(
            Date().addingTimeInterval(10 * 60),
            forKey: "com.bondex.notch.focus.endDate"
        )
        defaults.set(25 * 60.0, forKey: "com.bondex.notch.focus.duration")

        let restored = FocusTimerService(defaults: defaults, events: EventCenter())
        XCTAssertTrue(restored.snapshot.isRunning)
        XCTAssertEqual(restored.snapshot.duration, 25 * 60, accuracy: 0.01)
        XCTAssertGreaterThan(restored.snapshot.remaining, 9 * 60)

        restored.cancel()
    }
}

@MainActor
final class UpcomingMeetingTests: XCTestCase {

    func testMeetingBecomesCompactTenMinutesBeforeStart() {
        let now = Date()
        let meeting = UpcomingMeeting(
            id: "review",
            title: "Review",
            startDate: now.addingTimeInterval(9 * 60),
            endDate: now.addingTimeInterval(69 * 60),
            joinURL: nil
        )
        XCTAssertTrue(meeting.startsSoon(at: now))
        XCTAssertEqual(meeting.relativeString(at: now), "In 9 min")
    }

    func testDistantMeetingStaysOutOfCompactNotch() {
        let now = Date()
        let meeting = UpcomingMeeting(
            id: "later",
            title: "Later",
            startDate: now.addingTimeInterval(90 * 60),
            endDate: now.addingTimeInterval(120 * 60),
            joinURL: nil
        )
        XCTAssertFalse(meeting.startsSoon(at: now))
        XCTAssertTrue(meeting.isRelevantToHome(at: now))
    }

    func testSupportedMeetingLinkIsExtractedFromLocation() {
        let event = EKEvent(eventStore: EKEventStore())
        event.location = "Join at https://meet.google.com/abc-defg-hij"

        XCTAssertEqual(
            UpcomingMeetingService.joinURL(for: event)?.absoluteString,
            "https://meet.google.com/abc-defg-hij"
        )
    }

    func testLookalikeMeetingHostIsRejected() {
        let event = EKEvent(eventStore: EKEventStore())
        event.location = "https://meet.google.com.example.com/steal"

        XCTAssertNil(UpcomingMeetingService.joinURL(for: event))
    }
}

@MainActor
final class SystemHUDServiceTests: XCTestCase {

    func testBatteryHUDOnlyAppearsForPowerTransitions() {
        let service = SystemHUDService()
        var presentations: [SystemHUDPresentation] = []
        service.onPresentation = { presentations.append($0) }

        service.updateBattery(SystemSnapshot(
            batteryLevel: 0.72,
            isCharging: false,
            isPluggedIn: false
        ))
        XCTAssertTrue(presentations.isEmpty, "The first sample is only a baseline")

        service.updateBattery(SystemSnapshot(
            batteryLevel: 0.71,
            isCharging: false,
            isPluggedIn: false
        ))
        XCTAssertTrue(presentations.isEmpty, "Routine discharge should stay quiet")

        service.updateBattery(SystemSnapshot(
            batteryLevel: 0.71,
            isCharging: true,
            isPluggedIn: true
        ))
        XCTAssertEqual(
            presentations.last,
            SystemHUDPresentation(kind: .battery, level: 0.71, detail: "Charging")
        )
    }
}

final class FocusTimerCommandTests: XCTestCase {
    func testParsesFocusCommands() {
        XCTAssertEqual(
            FocusTimerCommand.parse(["BondexNotch", "--focus-start", "45"]),
            .command(.start(minutes: 45))
        )
        XCTAssertEqual(
            FocusTimerCommand.parse(["BondexNotch", "--focus-pause"]),
            .command(.pause)
        )
        XCTAssertEqual(
            FocusTimerCommand.parse(["BondexNotch", "--focus-cancel"]),
            .command(.cancel)
        )
    }

    func testRejectsInvalidFocusDuration() {
        guard case .invalid(let flag, _) = FocusTimerCommand.parse([
            "BondexNotch", "--focus-start", "999"
        ]) else {
            return XCTFail("Expected invalid duration")
        }
        XCTAssertEqual(flag, "--focus-start")
    }
}
