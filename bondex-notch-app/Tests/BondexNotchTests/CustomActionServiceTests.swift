import XCTest
@testable import BondexNotch

@MainActor
final class CustomActionServiceTests: XCTestCase {

    func testApplicationActionUsesBundleIdentifierAndFallbackPath() {
        var opened: (String?, String)?
        let service = CustomActionService(
            openApplication: { bundleIdentifier, path in
                opened = (bundleIdentifier, path)
                return true
            },
            runShortcut: { _ in false }
        )
        let action = CustomAction(
            title: "Calculator",
            target: .application(
                bundleIdentifier: "com.apple.calculator",
                path: "/System/Applications/Calculator.app"
            )
        )

        service.perform(action) { _ in nil }

        XCTAssertEqual(opened?.0, "com.apple.calculator")
        XCTAssertEqual(opened?.1, "/System/Applications/Calculator.app")
        XCTAssertEqual(
            service.feedback,
            CustomActionFeedback(message: "Opened Calculator", isError: false)
        )
    }

    func testApplicationFallbackRejectsArbitraryFiles() {
        XCTAssertNil(CustomActionService.fallbackApplicationURL(for: ""))
        XCTAssertNil(CustomActionService.fallbackApplicationURL(for: "/tmp/report.pdf"))
        XCTAssertNil(CustomActionService.fallbackApplicationURL(for: "/tmp/Fake.app"))
        XCTAssertNotNil(CustomActionService.fallbackApplicationURL(
            for: "/System/Applications/Calculator.app"
        ))
    }

    func testShortcutNameIsPassedAsOneArgumentWithoutShellParsing() {
        let name = "Morning; touch /tmp/should-not-run"
        var received: String?
        let service = CustomActionService(
            openApplication: { _, _ in false },
            runShortcut: {
                received = $0
                return true
            }
        )

        service.perform(
            CustomAction(title: "Morning", target: .appleShortcut(name: name))
        ) { _ in nil }

        XCTAssertEqual(received, name)
        XCTAssertEqual(CustomActionService.shortcutArguments(for: name), ["run", name])
    }

    func testWidgetActionReportsItsNewState() {
        let service = CustomActionService(
            openApplication: { _, _ in false },
            runShortcut: { _ in false }
        )
        var toggled: NotchTab?

        service.perform(
            CustomAction(title: "System", target: .toggleWidget(.system))
        ) { tab in
            toggled = tab
            return false
        }

        XCTAssertEqual(toggled, .system)
        XCTAssertEqual(
            service.feedback,
            CustomActionFeedback(message: "System disabled", isError: false)
        )
    }

    func testAllTargetKindsRoundTripThroughPreferences() throws {
        let actions = [
            CustomAction(
                title: "Notes",
                target: .application(
                    bundleIdentifier: "com.apple.Notes",
                    path: "/System/Applications/Notes.app"
                )
            ),
            CustomAction(title: "Log water", target: .appleShortcut(name: "Log water")),
            CustomAction(title: "Music", target: .toggleWidget(.music))
        ]
        var preferences = Preferences()
        preferences.customActions = actions

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)

        XCTAssertEqual(decoded.customActions, actions)
    }
}
