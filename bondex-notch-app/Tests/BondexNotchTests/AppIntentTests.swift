import AppKit
import XCTest
@testable import BondexNotch

final class AppIntentTests: XCTestCase {
    func testBuiltInIntentProfilesUseTheStableProfileIdentifiers() {
        let expected = Dictionary(uniqueKeysWithValues: NotchProfile.defaults.map {
            ($0.name.lowercased(), $0.id)
        })

        XCTAssertEqual(BondexProfileIntentOption.work.profileID, expected["work"])
        XCTAssertEqual(BondexProfileIntentOption.meeting.profileID, expected["meeting"])
        XCTAssertEqual(BondexProfileIntentOption.media.profileID, expected["media"])
        XCTAssertEqual(BondexProfileIntentOption.gaming.profileID, expected["gaming"])
    }

    func testEveryIntentWidgetMapsToARealNotchTab() {
        for widget in BondexWidgetIntentOption.allCases {
            XCTAssertNotNil(NotchTab(rawValue: widget.rawValue))
        }
    }

    func testIntentActionsUseAClosedKnownCommandSet() {
        XCTAssertEqual(
            AppIntentCommand.Action.allCasesForTesting.map(\.rawValue),
            [
                "automaticProfiles",
                "activateProfile",
                "createCapture",
                "showWidget",
                "startFocus"
            ]
        )
    }

    @MainActor
    func testEnvironmentValidatesAndRoutesIntentCommands() throws {
        let suite = "AppIntentTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let environment = AppEnvironment(
            screen: try XCTUnwrap(NSScreen.main),
            defaults: defaults
        )

        XCTAssertTrue(environment.performAppIntentCommand(.automaticProfiles))
        XCTAssertEqual(environment.settings.preferences.smartProfileMode, .automatic)

        XCTAssertFalse(environment.performAppIntentCommand(
            .activateProfile,
            value: UUID().uuidString
        ))

        environment.quickCapture.draft = "Unfinished draft"
        XCTAssertTrue(environment.performAppIntentCommand(
            .createCapture,
            value: "Created through an intent"
        ))
        XCTAssertEqual(environment.quickCapture.draft, "Unfinished draft")
        XCTAssertEqual(environment.quickCapture.items.first?.text, "Created through an intent")
        XCTAssertEqual(environment.notch.tab, .capture)
        XCTAssertTrue(environment.notch.state.isExpanded)

        XCTAssertFalse(environment.performAppIntentCommand(.showWidget, value: "unknown"))

        XCTAssertTrue(environment.performAppIntentCommand(.startFocus, minutes: 500))
        XCTAssertEqual(environment.focusTimer.snapshot.duration, 180 * 60)
        environment.focusTimer.cancel()

        environment.settings.preferences.quickCaptureEnabled = false
        XCTAssertFalse(environment.performAppIntentCommand(
            .createCapture,
            value: "Should not be saved"
        ))

        environment.settings.preferences.focusTimerEnabled = false
        XCTAssertFalse(environment.performAppIntentCommand(.startFocus, minutes: 25))
        XCTAssertFalse(environment.focusTimer.snapshot.isActive)
    }
}

private extension AppIntentCommand.Action {
    static var allCasesForTesting: [Self] {
        [.automaticProfiles, .activateProfile, .createCapture, .showWidget, .startFocus]
    }
}
