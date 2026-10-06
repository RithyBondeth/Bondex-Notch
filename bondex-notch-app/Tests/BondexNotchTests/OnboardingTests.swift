import XCTest
@testable import BondexNotch

final class OnboardingTests: XCTestCase {

    /// A fresh install has no saved preferences and sees the welcome.
    func testANewInstallSeesTheWelcome() {
        XCTAssertFalse(Preferences().hasCompletedOnboarding)
    }

    /// Anyone updating already has saved preferences: no welcome for them, and
    /// no pause on their media or Downloads features while it waits.
    func testAnExistingInstallSkipsTheWelcome() throws {
        let stored = #"{"musicWidgetEnabled":true}"#
        let decoded = try XCTUnwrap(SettingsStore.decode(Data(stored.utf8)))
        XCTAssertTrue(decoded.hasCompletedOnboarding)
    }

    func testChoosingAppliesEveryFeatureAndFinishes() {
        var preferences = Preferences()
        var choices = OnboardingChoices(preferences: preferences)
        choices.media = false
        choices.downloads = true
        choices.meetings = true

        choices.apply(to: &preferences)

        XCTAssertFalse(preferences.musicWidgetEnabled)
        XCTAssertTrue(preferences.fileActivityEnabled)
        XCTAssertTrue(preferences.upcomingMeetingsEnabled)
        XCTAssertTrue(preferences.hasCompletedOnboarding)
    }

    /// Agent notifications only mean anything with agents on, so turning agents
    /// off neither keeps them nor asks for notification permission.
    func testNotificationsFollowAgents() {
        var preferences = Preferences()
        var choices = OnboardingChoices(preferences: preferences)
        choices.agents = false
        choices.agentNotifications = true

        choices.apply(to: &preferences)

        XCTAssertFalse(preferences.notifyWhenAgentNeedsYou)
        XCTAssertFalse(choices.permissionsToRequest.contains(.notifications))
    }

    /// Calendar and notification access are asked for up front, and only for
    /// what was chosen. Automation and Downloads are left to macOS, which asks
    /// the first time the feature reads.
    func testOnlyChosenPermissionsAreRequested() {
        var choices = OnboardingChoices(preferences: Preferences())
        choices.clipboard = false
        choices.meetings = false
        choices.agents = true
        choices.agentNotifications = true
        XCTAssertEqual(choices.permissionsToRequest, [.notifications])

        choices.meetings = true
        choices.agentNotifications = false
        XCTAssertEqual(choices.permissionsToRequest, [.calendar])
    }

    /// macOS 15.4 asks before an app reads the clipboard, so choosing history
    /// asks then — not on the first copy afterwards.
    func testChoosingClipboardHistoryAsksForClipboardAccess() {
        var choices = OnboardingChoices(preferences: Preferences())
        choices.clipboard = true
        XCTAssertEqual(
            choices.permissionsToRequest.contains(.clipboard),
            OnboardingChoices.clipboardNeedsPermission
        )
        choices.clipboard = false
        XCTAssertFalse(choices.permissionsToRequest.contains(.clipboard))
    }
}
