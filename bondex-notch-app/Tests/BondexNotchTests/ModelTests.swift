import AppKit
import XCTest
@testable import BondexNotch

final class LicenseValidatorTests: XCTestCase {

    func testGeneratedKeysValidate() {
        for payload in ["BEEF1234", "00000000", "FFFFFFFF", "0A1B2C3D"] {
            let key = try? XCTUnwrap(LicenseValidator.makeKey(payload: payload))
            XCTAssertNotNil(key, "Failed to generate a key for \(payload)")
            XCTAssertTrue(LicenseValidator.validate(key ?? ""), "\(payload) round-trip failed")
        }
    }

    func testKeysAreCaseAndWhitespaceInsensitive() throws {
        let key = try XCTUnwrap(LicenseValidator.makeKey(payload: "BEEF1234"))
        XCTAssertTrue(LicenseValidator.validate("  \(key.lowercased())  "))
    }

    func testMalformedKeysAreRejected() {
        let bad = [
            "",
            "BNDX-BEEF-1234",                 // too few groups
            "XXXX-BEEF-1234-0000",            // wrong prefix
            "BNDX-BEEF-1234-0000",            // wrong checksum
            "BNDX-BEEF-1234-ZZZZ",            // non-hex checksum
            "BNDX-BEE-1234-0000",             // wrong group length
            "BNDX-GGGG-1234-0000"             // non-hex payload
        ]
        for key in bad {
            XCTAssertFalse(LicenseValidator.validate(key), "\(key) should not validate")
        }
    }

    func testPayloadMustBeEightHexDigits() {
        XCTAssertNil(LicenseValidator.makeKey(payload: "SHORT"))
        XCTAssertNil(LicenseValidator.makeKey(payload: "TOOLONGPAYLOAD"))
        XCTAssertNil(LicenseValidator.makeKey(payload: "ZZZZZZZZ"))
    }

    @MainActor
    func testCompleteAppIsAvailableForTwentyFourHours() throws {
        let suiteName = "LicenseTrialTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = SettingsStore(defaults: defaults, now: { currentDate })

        XCTAssertEqual(
            settings.licenseAccess,
            .trial(expiresAt: currentDate.addingTimeInterval(SettingsStore.trialDuration))
        )
        XCTAssertTrue(settings.canUseApp)

        currentDate.addTimeInterval(SettingsStore.trialDuration)
        settings.refreshLicenseAccess()
        XCTAssertEqual(settings.licenseAccess, .expired)
        XCTAssertFalse(settings.canUseApp)
    }

    @MainActor
    func testPurchasedLicenseUnlocksAnExpiredTrial() throws {
        let suiteName = "LicenseActivationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = SettingsStore(defaults: defaults, now: { currentDate })

        currentDate.addTimeInterval(SettingsStore.trialDuration + 1)
        settings.refreshLicenseAccess()
        XCTAssertEqual(settings.licenseAccess, .expired)

        settings.preferences.licenseKey = try XCTUnwrap(
            LicenseValidator.makeKey(payload: "BEEF1234")
        )
        XCTAssertEqual(settings.licenseAccess, .licensed)
        XCTAssertTrue(settings.canUseApp)
    }

    @MainActor
    func testTrialStartPersistsAcrossRelaunches() throws {
        let suiteName = "LicensePersistenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let first = SettingsStore(defaults: defaults, now: { currentDate })
        let originalStart = first.trialStartedAt

        currentDate.addTimeInterval(60 * 60)
        let relaunched = SettingsStore(defaults: defaults, now: { currentDate })
        XCTAssertEqual(relaunched.trialStartedAt, originalStart)
        XCTAssertEqual(
            relaunched.trialTimeRemaining,
            SettingsStore.trialDuration - 60 * 60,
            accuracy: 0.01
        )
    }
}

@MainActor
final class EventCenterTests: XCTestCase {

    func testIdenticalBackToBackEventsAreCollapsed() {
        let center = EventCenter()
        center.post(NotchEvent(kind: .download, title: "a.zip", subtitle: "1 MB"))
        center.post(NotchEvent(kind: .download, title: "a.zip", subtitle: "1 MB"))

        XCTAssertEqual(center.events.count, 1, "A repeated report should not spam the feed")
    }

    func testDifferentEventsAreAllKept() {
        let center = EventCenter()
        center.post(NotchEvent(kind: .download, title: "a.zip", subtitle: "1 MB"))
        center.post(NotchEvent(kind: .download, title: "a.zip", subtitle: "2 MB"))
        center.post(NotchEvent(kind: .music, title: "a.zip", subtitle: "1 MB"))

        XCTAssertEqual(center.events.count, 3)
    }

    func testNewestEventIsFirstAndBecomesLatest() {
        let center = EventCenter()
        center.post(NotchEvent(kind: .music, title: "first"))
        center.post(NotchEvent(kind: .music, title: "second"))

        XCTAssertEqual(center.events.first?.title, "second")
        XCTAssertEqual(center.latest?.title, "second")
    }

    func testFeedIsBounded() {
        let center = EventCenter()
        for index in 0..<200 {
            center.post(NotchEvent(kind: .system, title: "event \(index)"))
        }
        XCTAssertLessThanOrEqual(center.events.count, 60)
        XCTAssertEqual(center.events.first?.title, "event 199", "Newest must survive trimming")
    }

    func testClearResetsEverything() {
        let center = EventCenter()
        center.post(NotchEvent(kind: .shelf, title: "x"))
        center.clear()

        XCTAssertTrue(center.events.isEmpty)
        XCTAssertNil(center.latest)
    }
}

@MainActor
final class NotchGeometryTests: XCTestCase {

    private func geometry(hasNotch: Bool) -> NotchGeometry {
        NotchGeometry(
            notchSize: hasNotch ? CGSize(width: 179, height: 32) : CGSize(width: 190, height: 32),
            hasHardwareNotch: hasNotch,
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956)
        )
    }

    func testWindowIsTopCentredOnTheScreen() {
        let geometry = geometry(hasNotch: true)
        let frame = geometry.windowFrame

        XCTAssertEqual(frame.midX, geometry.screenFrame.midX, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, geometry.screenFrame.maxY, accuracy: 0.5,
                       "The panel must hang from the very top of the display")
    }

    func testHitRectIsTopCentredAndMatchesTheStateSize() {
        let geometry = geometry(hasNotch: true)

        for state in [NotchState.collapsed, .peek, .expanded] {
            let content = geometry.contentSize(for: state)
            let rect = geometry.hitRect(for: state)

            XCTAssertEqual(rect.size, content)
            XCTAssertEqual(rect.midX, geometry.windowSize.width / 2, accuracy: 0.5)
            XCTAssertEqual(rect.maxY, geometry.windowSize.height, accuracy: 0.5)
        }
    }

    func testEveryStateFitsInsideTheWindow() {
        let geometry = geometry(hasNotch: true)
        let bounds = CGRect(origin: .zero, size: geometry.windowSize)

        for state in [NotchState.collapsed, .peek, .expanded] {
            XCTAssertTrue(bounds.contains(geometry.hitRect(for: state)),
                          "\(state) escapes the fixed window footprint")
        }
    }

    func testStatesGrowMonotonically() {
        let geometry = geometry(hasNotch: true)
        let collapsed = geometry.contentSize(for: .collapsed)
        let peek = geometry.contentSize(for: .peek)
        let expanded = geometry.contentSize(for: .expanded)

        XCTAssertLessThan(collapsed.width, peek.width)
        XCTAssertLessThan(peek.width, expanded.width)
        XCTAssertLessThanOrEqual(collapsed.height, peek.height)
        XCTAssertLessThan(peek.height, expanded.height)
    }

    func testSystemHUDGetsAReadableCompactWidth() {
        let geometry = geometry(hasNotch: true)
        let media = geometry.contentSize(for: .peek, peek: .media)
        let hud = geometry.contentSize(for: .peek, peek: .systemHUD)
        let expanded = geometry.contentSize(for: .expanded)

        XCTAssertGreaterThan(hud.width, media.width)
        XCTAssertLessThan(hud.width, expanded.width)
        XCTAssertEqual(hud.height, media.height)
    }

    func testHoverRectAlwaysContainsTheStateItGuards() {
        let geometry = geometry(hasNotch: true)

        for state in [NotchState.collapsed, .peek, .expanded] {
            let hover = geometry.hoverRect(for: state)
            let screen = geometry.screenRect(for: state)
            XCTAssertTrue(hover.contains(screen),
                          "\(state) hover zone must not be smaller than the panel")
            XCTAssertEqual(hover.maxY, screen.maxY, accuracy: 0.5,
                           "Padding above the top of the display is wasted")
        }
    }

    func testDisplaysWithoutANotchStillGetAUsableTarget() {
        let geometry = geometry(hasNotch: false)
        XCTAssertGreaterThan(geometry.notchSize.width, 0)
        XCTAssertGreaterThan(geometry.notchSize.height, 0)
        XCTAssertFalse(geometry.hasHardwareNotch)
    }
}

final class FormattingTests: XCTestCase {

    func testSystemHUDClampsAndRoundsPercentages() {
        XCTAssertEqual(SystemHUDPresentation(kind: .volume, level: -1).percentage, 0)
        XCTAssertEqual(SystemHUDPresentation(kind: .brightness, level: 0.684).percentage, 68)
        XCTAssertEqual(SystemHUDPresentation(kind: .battery, level: 2).percentage, 100)
    }

    func testClockStringFormatsMinutesAndSeconds() {
        XCTAssertEqual(TimeInterval(0).clockString, "0:00")
        XCTAssertEqual(TimeInterval(9).clockString, "0:09")
        XCTAssertEqual(TimeInterval(65).clockString, "1:05")
        XCTAssertEqual(TimeInterval(489).clockString, "8:09")
    }

    func testClockStringHandlesGarbageInput() {
        XCTAssertEqual(TimeInterval(-5).clockString, "0:00")
        XCTAssertEqual(TimeInterval.infinity.clockString, "0:00")
        XCTAssertEqual(TimeInterval.nan.clockString, "0:00")
    }
}

final class NowPlayingTests: XCTestCase {

    private func track(title: String, position: TimeInterval) -> NowPlaying {
        NowPlaying(
            source: .music,
            title: title,
            artist: "Marconi Union",
            album: "Ambient Transmissions",
            isPlaying: true,
            duration: 489,
            position: position,
            artwork: nil
        )
    }

    func testProgressIsClampedAndSafeAtZeroDuration() {
        XCTAssertEqual(track(title: "a", position: 0).progress, 0, accuracy: 0.001)
        XCTAssertEqual(track(title: "a", position: 489).progress, 1, accuracy: 0.001)
        XCTAssertEqual(track(title: "a", position: 900).progress, 1, accuracy: 0.001)

        var zeroLength = track(title: "a", position: 12)
        zeroLength.duration = 0
        XCTAssertEqual(zeroLength.progress, 0, "Must not divide by zero")
    }

    func testSubSecondPositionDriftIsNotAChange() {
        // The service polls once a second; treating drift as a change would
        // republish the whole track and restart artwork loading.
        XCTAssertEqual(track(title: "a", position: 10.0), track(title: "a", position: 10.5))
        XCTAssertNotEqual(track(title: "a", position: 10.0), track(title: "a", position: 14.0))
    }

    func testTrackKeyIgnoresPlaybackPosition() {
        XCTAssertEqual(
            track(title: "Weightless", position: 3).trackKey,
            track(title: "Weightless", position: 300).trackKey
        )
        XCTAssertNotEqual(
            track(title: "Weightless", position: 3).trackKey,
            track(title: "Something Else", position: 3).trackKey
        )
    }
}
