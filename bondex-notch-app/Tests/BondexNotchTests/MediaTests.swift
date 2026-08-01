import Foundation
import XCTest
@testable import BondexNotch

/// The browser reader's JavaScript is embedded in an AppleScript string literal
/// and its result is split on a control character. Both of those are easy to
/// break by editing the script without thinking about the transport.
final class BrowserScriptTests: XCTestCase {

    private var everyScript: [(name: String, source: String)] {
        let reader = BrowserMediaReader(engine: AppleScriptEngine())
        return [
            ("read", BrowserMediaReader.readScript),
            ("playPause", reader.script(for: .playPause)),
            ("next", reader.script(for: .next)),
            ("previous", reader.script(for: .previous))
        ]
    }

    func testScriptsSurviveAppleScriptQuoting() {
        for (name, source) in everyScript {
            let quoted = source.appleScriptLiteral

            // Escaping is lossless, so quotes and backslashes would technically
            // survive — but every one of them is a chance for a future edit to
            // land inside the literal wrongly, and none are needed.
            XCTAssertFalse(source.contains("\""), "\(name) should use single quotes only")
            XCTAssertFalse(source.contains("\\"), "\(name) should avoid backslashes")

            XCTAssertTrue(quoted.hasPrefix("\""), "\(name) is not a quoted literal")
            XCTAssertTrue(quoted.hasSuffix("\""), "\(name) is not a quoted literal")
            XCTAssertFalse(source.contains("\n"), "\(name) must be one line for the literal")
        }
    }

    func testQuotingEscapesWhatItMust() {
        XCTAssertEqual("plain".appleScriptLiteral, "\"plain\"")
        XCTAssertEqual("say \"hi\"".appleScriptLiteral, "\"say \\\"hi\\\"\"")
        XCTAssertEqual("back\\slash".appleScriptLiteral, "\"back\\\\slash\"")
    }

    func testSeparatorCannotOccurInATrackTitle() {
        // The payload joins its fields with String.fromCharCode(1), which is not
        // representable in any text a page would put in a title.
        XCTAssertEqual(BrowserMediaReader.separator, "\u{01}")
        XCTAssertEqual(BrowserMediaReader.separator.count, 1)
    }

    func testReadScriptReportsEveryFieldTheParserExpects() {
        // `probe` indexes fields 0...8; the payload must join exactly that many.
        let script = BrowserMediaReader.readScript
        for field in ["b.duration", "b.currentTime", "location.hostname"] {
            XCTAssertTrue(script.contains(field), "read script lost \(field)")
        }
        XCTAssertTrue(script.contains("mediaSession"), "read script lost its metadata source")
    }
}

final class MediaHostTests: XCTestCase {

    func testKnownHostsMatchTheirSubdomains() {
        for host in [
            "youtube.com", "www.youtube.com", "music.youtube.com",
            "open.spotify.com", "soundcloud.com", "www.twitch.tv"
        ] {
            XCTAssertTrue(BrowserMediaReader.isKnownMediaHost(host), "\(host) should match")
        }
    }

    func testLookalikeHostsDoNotMatch() {
        // Suffix matching without the dot would let any of these through.
        for host in ["notyoutube.com", "youtube.com.evil.test", "myvimeo.com", "max.example"] {
            XCTAssertFalse(BrowserMediaReader.isKnownMediaHost(host), "\(host) should not match")
        }
    }
}

final class BrowserTitleTests: XCTestCase {

    func testSiteSuffixesAreRemoved() {
        XCTAssertEqual(BrowserMediaReader.strippedTitle("Weightless - YouTube"), "Weightless")
        XCTAssertEqual(BrowserMediaReader.strippedTitle("Some Set - Twitch"), "Some Set")
    }

    func testUnreadCounterPrefixIsRemoved() {
        // Browsers put the notification count in the tab title; YouTube's live
        // pages do it constantly.
        XCTAssertEqual(BrowserMediaReader.strippedTitle("(5) Live Match - YouTube"), "Live Match")
        XCTAssertEqual(BrowserMediaReader.strippedTitle("(12) Weightless"), "Weightless")
    }

    func testParenthesesThatAreNotACounterAreKept() {
        XCTAssertEqual(
            BrowserMediaReader.strippedTitle("(Don't Fear) The Reaper"),
            "(Don't Fear) The Reaper"
        )
        XCTAssertEqual(BrowserMediaReader.strippedTitle("(Live) - YouTube"), "(Live)")
    }

    func testTitlesWithoutDecorationAreUntouched() {
        XCTAssertEqual(BrowserMediaReader.strippedTitle("Weightless"), "Weightless")
        XCTAssertEqual(BrowserMediaReader.strippedTitle(""), "")
    }

    func testAWholeAtlasWindowTitleCleansUp() {
        // The real thing, verbatim from a live stream, minus the marker the
        // reader strips before calling this.
        let raw = "(5) [ផ្សាយផ្ទាល់] | MSC នៅ EWC វគ្គជម្រុះ ថ្ងៃទី 2 | (KH) - YouTube "
        XCTAssertEqual(
            BrowserMediaReader.strippedTitle(raw),
            "[ផ្សាយផ្ទាល់] | MSC នៅ EWC វគ្គជម្រុះ ថ្ងៃទី 2 | (KH)"
        )
    }
}

final class WindowTitleFallbackTests: XCTestCase {

    func testAtlasIsReadThroughItsWindowTitle() {
        XCTAssertTrue(MediaApp.atlas.readsByWindowTitleOnly)
        XCTAssertEqual(MediaApp.atlas.audibleWindowMarker, "🔊")
    }

    func testBrowsersThatCanRunJavaScriptDoNotUseTheFallback() {
        // The fallback is title-only and cannot drive playback, so it must never
        // pre-empt a browser that could give the real thing.
        for app in [MediaApp.safari, .chrome, .brave, .edge] {
            XCTAssertFalse(app.readsByWindowTitleOnly, "\(app.displayName)")
        }
    }

    func testTitleOnlyPlaybackReportsItCannotBeDriven() {
        let track = NowPlaying(
            source: .atlas,
            title: "Live Match",
            artist: "",
            album: "",
            isPlaying: true,
            duration: 0,
            position: 0,
            artwork: nil,
            artworkURL: nil,
            supportsTransport: false
        )
        XCTAssertFalse(track.supportsTransport)
        XCTAssertTrue(track.isLive, "No duration is available from a window title")
    }
}

final class MediaAppTests: XCTestCase {

    func testBrowsersWithTheSwitchExplainWhereItIs() {
        for app in MediaApp.browsers where app.canEnableJavaScript {
            XCTAssertFalse(app.javaScriptHint.isEmpty, "\(app.displayName) has no hint")
            XCTAssertTrue(
                app.javaScriptHint.contains("Apple Events"),
                "\(app.displayName)'s hint should name the setting"
            )
        }
    }

    func testBrowsersWithoutTheSwitchSendNobodyLookingForIt() {
        // Atlas parses `execute javascript` but permits it nowhere, and has no
        // menu item to change that. Telling the user to go and enable it would
        // point them at something that does not exist.
        for app in MediaApp.browsers where !app.canEnableJavaScript {
            XCTAssertTrue(
                app.javaScriptHint.isEmpty,
                "\(app.displayName) cannot be enabled, so it must not ask the user to"
            )
        }
    }

    func testEveryBrowserIsReadableSomeHow() {
        // A browser that can neither run JavaScript nor mark its audible window
        // is unreadable, and listing it only costs Apple Events every poll.
        for app in MediaApp.browsers {
            XCTAssertTrue(
                app.canEnableJavaScript || app.audibleWindowMarker != nil,
                "\(app.displayName) has no way to be read at all"
            )
        }
    }

    func testPlayersHaveNoJavaScriptHint() {
        for app in MediaApp.players {
            XCTAssertTrue(app.javaScriptHint.isEmpty)
            XCTAssertFalse(app.isBrowser)
        }
    }

    func testBundleIdentifiersAreUnique() {
        let ids = MediaApp.all.map(\.bundleIdentifier)
        XCTAssertEqual(ids.count, Set(ids).count, "Two entries claim the same app")
    }
}

@MainActor
final class ExpandedSizingTests: XCTestCase {

    private let geometry = NotchGeometry(
        notchSize: CGSize(width: 179, height: 32),
        hasHardwareNotch: true,
        screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956)
    )

    func testContentSizedTabsAreMeasuredRatherThanFixed() {
        // Home, Music, and System report no fixed height, which is what lets the
        // panel hug their actual content.
        XCTAssertNil(NotchTab.home.widgetHeight)
        XCTAssertNil(NotchTab.music.widgetHeight)
        XCTAssertNil(NotchTab.system.widgetHeight)
    }

    func testListTabsKeepAStableArea() {
        // A panel that resized as feed items arrived and aged out would be worse
        // than one that stays put.
        for tab in [NotchTab.live, .files, .activity, .shelf] {
            XCTAssertNotNil(tab.widgetHeight, "\(tab.rawValue) would resize as its list changed")
        }
    }

    func testAMeasuredPanelIsHitTestedWhereItIsDrawn() {
        // The rect has to follow the measured height, or the panel keeps claiming
        // clicks in the empty space below whatever it actually drew.
        let short = geometry.hitRect(ofSize: CGSize(width: 560, height: 150))
        let tall = geometry.hitRect(ofSize: CGSize(width: 560, height: 224))

        XCTAssertLessThan(short.height, tall.height)
        XCTAssertEqual(short.maxY, tall.maxY, accuracy: 0.5, "Both hang from the top")
        XCTAssertEqual(short.midX, tall.midX, accuracy: 0.5)
        XCTAssertGreaterThan(short.minY, tall.minY, "The shorter panel stops higher up")
    }

    func testMeasuredRectsAgreeWithTheStateBasedOnes() {
        for state in [NotchState.collapsed, .peek, .expanded] {
            let size = geometry.contentSize(for: state)
            XCTAssertEqual(geometry.hitRect(ofSize: size), geometry.hitRect(for: state))
            XCTAssertEqual(geometry.screenRect(ofSize: size), geometry.screenRect(for: state))
        }
    }

    func testTheCeilingClearsTheTallestTab() {
        // A ceiling tuned to exactly fit is one that clips the moment a widget
        // grows a row, or on a Mac whose notch is taller. Chrome is the notch
        // inset plus the tab strip, divider and the panel's own padding.
        let chrome = geometry.notchSize.height + 80
        let tallest = NotchTab.allCases.compactMap(\.widgetHeight).max() ?? 0

        XCTAssertLessThan(
            chrome + tallest,
            NotchGeometry.expandedContentSize.height,
            "The tallest tab would be clamped, which shows up as a clipped bottom edge"
        )
    }

    func testTheWholePanelStillFitsItsWindow() {
        let bounds = CGRect(origin: .zero, size: geometry.windowSize)
        XCTAssertTrue(bounds.contains(geometry.hitRect(ofSize: NotchGeometry.expandedContentSize)))
    }
}

final class BannerPolicyTests: XCTestCase {

    func testPlaybackNeverBanners() {
        // The peek shows artwork and the equaliser for as long as playback lasts,
        // deliberately without the title. A banner would put that title straight
        // back over the menu bar for a few seconds every time a track changed.
        XCTAssertFalse(NotchEvent.Kind.music.deservesBanner)
    }

    func testEverythingWithoutItsOwnIndicatorBanners() {
        // These have no standing representation in the notch, so a banner is the
        // only time the user would ever see them.
        for kind in [NotchEvent.Kind.download, .system, .shelf, .live, .app] {
            XCTAssertTrue(kind.deservesBanner, "\(kind.rawValue) would go unseen")
        }
    }
}

@MainActor
final class PeekWidthTests: XCTestCase {

    private let geometry = NotchGeometry(
        notchSize: CGSize(width: 179, height: 32),
        hasHardwareNotch: true,
        screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956)
    )

    func testPlaybackPeekIsNarrowerThanABanner() {
        // Playing shows artwork and the equaliser only, so the strips can sit
        // close to the notch; a banner has to carry a line of text.
        let playing = geometry.contentSize(for: .peek, peek: .media)
        let banner = geometry.contentSize(for: .peek, peek: .banner)

        XCTAssertLessThan(playing.width, banner.width)
        XCTAssertEqual(playing.height, banner.height, "Only the width should differ")
    }

    func testPlaybackPeekStillClearsTheNotchOnBothSides() {
        let playing = geometry.contentSize(for: .peek, peek: .media)
        let perSide = (playing.width - geometry.notchSize.width) / 2

        XCTAssertGreaterThan(perSide, 40, "No room for artwork beside the notch")
    }

    func testBothPeeksSitBetweenCollapsedAndExpanded() {
        let collapsed = geometry.contentSize(for: .collapsed)
        let expanded = geometry.contentSize(for: .expanded)

        for content in [PeekContent.media, .live, .agent(agents: 1), .agent(agents: 3), .banner] {
            let peek = geometry.contentSize(for: .peek, peek: content)
            XCTAssertLessThan(collapsed.width, peek.width)
            XCTAssertLessThan(peek.width, expanded.width)
        }
    }

    func testHitTestingFollowsTheNarrowerPeek() {
        // The panel must not keep claiming clicks in a margin it stopped drawing.
        let playing = geometry.hitRect(for: .peek, peek: .media)
        let banner = geometry.hitRect(for: .peek, peek: .banner)

        XCTAssertLessThan(playing.width, banner.width)
        XCTAssertTrue(banner.contains(playing))
    }
}

@MainActor
final class PreferencesDecodingTests: XCTestCase {

    func testSettingsWrittenBeforeAFieldExistedStillLoad() throws {
        // A blob from a build that predates hoverDelay and browserMediaEnabled.
        // The synthesized decoder rejects this outright, which would throw away
        // every other setting in it.
        let old = """
        {"accent":"violet","motionSpeed":"snappy","musicWidgetEnabled":false,
         "systemWidgetEnabled":true,"fileActivityEnabled":true,
         "activityFeedEnabled":true,"shelfEnabled":true,"expandOnHover":false,
         "closeDelay":0.75,"peekWhilePlaying":true,"launchAtLogin":true,
         "licenseKey":""}
        """
        let decoded = try XCTUnwrap(SettingsStore.decode(Data(old.utf8)))

        // Everything the user had chosen survives.
        XCTAssertEqual(decoded.accent, .violet)
        XCTAssertEqual(decoded.motionSpeed, .snappy)
        XCTAssertFalse(decoded.musicWidgetEnabled)
        XCTAssertFalse(decoded.expandOnHover)
        XCTAssertEqual(decoded.closeDelay, 0.75, accuracy: 0.0001)
        XCTAssertTrue(decoded.launchAtLogin)

        // And the fields it had never heard of get their defaults.
        XCTAssertEqual(decoded.hoverDelay, Preferences().hoverDelay, accuracy: 0.0001)
        XCTAssertEqual(decoded.browserMediaEnabled, Preferences().browserMediaEnabled)
        XCTAssertEqual(
            decoded.showSystemSummaryOnHome,
            Preferences().showSystemSummaryOnHome
        )
        XCTAssertEqual(
            decoded.customLiveActivitiesEnabled,
            Preferences().customLiveActivitiesEnabled
        )
        XCTAssertEqual(decoded.panelWidth, Preferences().panelWidth, accuracy: 0.0001)
        XCTAssertEqual(decoded.panelStyle, Preferences().panelStyle)
        XCTAssertEqual(decoded.widgetOrder, NotchTab.allCases)
    }

    func testUnknownFieldsFromANewerBuildAreIgnored() {
        let future = """
        {"accent":"ocean","somethingAddedLater":42,"closeDelay":0.4}
        """
        let decoded = SettingsStore.decode(Data(future.utf8))
        XCTAssertEqual(decoded?.accent, .ocean)
        XCTAssertEqual(decoded?.closeDelay ?? 0, 0.4, accuracy: 0.0001)
    }

    func testGarbageIsRejectedRatherThanHalfApplied() {
        XCTAssertNil(SettingsStore.decode(Data("not json".utf8)))
    }

    func testARoundTripPreservesEverything() throws {
        var original = Preferences()
        original.accent = .forest
        original.hoverDelay = 0.42
        original.browserMediaEnabled = false
        original.accent = .custom
        original.customAccentHex = "12ABEF"
        original.panelStyle = .tinted
        original.panelWidth = 640
        original.panelOpacity = 0.8
        original.bottomCornerRadius = 32
        original.flareRadius = 17
        original.rimStrength = 0.4
        original.shadowStrength = 0.2
        original.widgetOrder = [.home, .activity, .music, .system, .live, .shelf, .files]
        original.licenseKey = "BNDX-BEEF-1234-0000"

        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(SettingsStore.decode(data), original)
    }

    func testWidgetOrderRepairsDuplicatesAndMissingTabs() {
        let suite = "com.bondex.notch.tests.order.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        store.preferences.widgetOrder = [.shelf, .home, .shelf]

        XCTAssertEqual(
            store.orderedTabs,
            [.shelf, .home, .music, .system, .live, .files, .activity]
        )
    }

    func testANewSystemTabLandsBesideMusicWithoutResettingCustomOrder() {
        let suite = "com.bondex.notch.tests.system-order.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        store.preferences.widgetOrder = [.activity, .home, .music, .shelf, .files]

        XCTAssertEqual(
            store.orderedTabs,
            [.activity, .home, .music, .system, .live, .shelf, .files]
        )
    }
}

final class NowPlayingInterpolationTests: XCTestCase {

    private func track(isPlaying: Bool, position: TimeInterval, duration: TimeInterval = 200)
    -> NowPlaying {
        NowPlaying(
            source: .music,
            title: "Weightless",
            artist: "Marconi Union",
            album: "Ambient Transmissions",
            isPlaying: isPlaying,
            duration: duration,
            position: position,
            artwork: nil,
            artworkURL: nil,
            sampledAt: Date()
        )
    }

    func testPositionAdvancesWithTheClockWhilePlaying() {
        let sample = track(isPlaying: true, position: 10)
        let later = sample.sampledAt.addingTimeInterval(2.5)
        XCTAssertEqual(sample.position(at: later), 12.5, accuracy: 0.001)
    }

    func testPositionIsFrozenWhilePaused() {
        let sample = track(isPlaying: false, position: 10)
        let later = sample.sampledAt.addingTimeInterval(30)
        XCTAssertEqual(sample.position(at: later), 10, accuracy: 0.001)
    }

    func testPositionNeverRunsPastTheEndOfTheTrack() {
        // Polling can stall behind a blocked Apple Event; the clock must not keep
        // walking the progress bar off the end.
        let sample = track(isPlaying: true, position: 195, duration: 200)
        let later = sample.sampledAt.addingTimeInterval(60)
        XCTAssertEqual(sample.position(at: later), 200, accuracy: 0.001)
        XCTAssertEqual(sample.progress(at: later), 1, accuracy: 0.001)
    }

    func testLiveStreamsHaveNoProgress() {
        // Browsers report an infinite duration for a live stream, which the reader
        // normalises to zero.
        let live = track(isPlaying: true, position: 42, duration: 0)
        XCTAssertTrue(live.isLive)
        XCTAssertEqual(live.progress(at: Date()), 0)
    }
}
