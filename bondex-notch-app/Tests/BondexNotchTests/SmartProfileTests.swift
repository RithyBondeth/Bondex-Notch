import XCTest
@testable import BondexNotch

final class SmartProfileTests: XCTestCase {

    func testConfiguredRulesAllHaveToMatch() {
        let rules = NotchProfileRules(
            applicationBundleIdentifiers: ["com.apple.dt.Xcode"],
            timeRangeEnabled: true,
            startHour: 9,
            endHour: 17,
            power: .powerAdapter,
            displays: .multiple,
            duringMeeting: true
        )
        let matching = context(
            app: "com.apple.dt.xcode",
            hour: 10,
            pluggedIn: true,
            displays: 2,
            meeting: true
        )

        XCTAssertTrue(rules.matches(matching))
        XCTAssertFalse(rules.matches(context(
            app: "com.apple.dt.Xcode",
            hour: 18,
            pluggedIn: true,
            displays: 2,
            meeting: true
        )))
        XCTAssertFalse(rules.matches(context(
            app: "com.apple.dt.Xcode",
            hour: 10,
            pluggedIn: false,
            displays: 2,
            meeting: true
        )))
    }

    func testOvernightTimeRangeWrapsAcrossMidnight() {
        let rules = NotchProfileRules(
            timeRangeEnabled: true,
            startHour: 22,
            endHour: 6
        )

        XCTAssertTrue(rules.matches(context(hour: 23)))
        XCTAssertTrue(rules.matches(context(hour: 3)))
        XCTAssertFalse(rules.matches(context(hour: 12)))
    }

    func testProfilesWithoutRulesStayManualOnly() {
        XCTAssertFalse(NotchProfileRules().matches(context()))
    }

    func testAutomaticMatchingUsesProfilePriority() {
        let first = NotchProfile(
            name: "First",
            rules: NotchProfileRules(timeRangeEnabled: true, startHour: 0, endHour: 0)
        )
        let second = NotchProfile(
            name: "Second",
            rules: NotchProfileRules(timeRangeEnabled: true, startHour: 0, endHour: 0)
        )

        XCTAssertEqual(
            SmartProfileService.matchingProfile(in: [first, second], context: context())?.id,
            first.id
        )
    }

    func testDefaultMeetingProfileOverridesAForegroundWorkApp() {
        let result = SmartProfileService.matchingProfile(
            in: NotchProfile.defaults,
            context: context(
                app: "com.apple.dt.Xcode",
                hour: 10,
                pluggedIn: true,
                displays: 1,
                meeting: true
            )
        )

        XCTAssertEqual(result?.name, "Meeting")
    }

    @MainActor
    func testManualAndOffModesApplyAndRestoreNonDestructively() {
        let suite = "SmartProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        settings.preferences.panelWidth = 610
        let profile = NotchProfile(
            name: "Compact",
            enabledTabs: [.home, .system],
            widgetOrder: [.system, .home],
            panelWidth: 460
        )
        settings.preferences.notchProfiles = [profile]
        settings.preferences.selectedProfileID = profile.id
        settings.preferences.smartProfileMode = .manual

        let service = SmartProfileService(settings: settings)
        service.refresh()

        XCTAssertEqual(settings.activeProfile?.id, profile.id)
        XCTAssertEqual(settings.effectivePanelWidth, 460)
        XCTAssertEqual(settings.orderedTabs, [.system, .home])
        XCTAssertFalse(settings.isTabEnabled(.music))

        service.turnOff()
        service.refresh()

        XCTAssertNil(settings.activeProfile)
        XCTAssertEqual(settings.effectivePanelWidth, 610)
        XCTAssertEqual(settings.preferences.panelWidth, 610)
    }

    private func context(
        app: String? = nil,
        hour: Int = 12,
        pluggedIn: Bool? = nil,
        displays: Int = 1,
        meeting: Bool = false
    ) -> SmartProfileContext {
        SmartProfileContext(
            activeApplicationBundleIdentifier: app,
            hour: hour,
            isPluggedIn: pluggedIn,
            displayCount: displays,
            meetingIsActive: meeting
        )
    }
}
