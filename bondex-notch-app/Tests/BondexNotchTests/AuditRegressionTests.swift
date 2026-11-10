import AppKit
import Combine
import XCTest
@testable import BondexNotch

/// Regression coverage for the October 2026 audit. Each test names the
/// behaviour that was broken, so a failure here reads as the bug coming back.

// MARK: - Pointer at the top edge

final class TopEdgePointerTests: XCTestCase {

    private let geometry = NotchGeometry(
        notchSize: CGSize(width: 185, height: 32),
        hasHardwareNotch: true,
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
    )

    /// Measured on a 14" MacBook Pro: a cursor pushed against the top of the
    /// display reports y equal to the screen's maxY. `CGRect.contains` rejects
    /// that row, so the notch never opened for a pointer thrown at it.
    func testAPointerOnTheTopRowIsOverTheNotch() {
        let topRow = CGPoint(x: geometry.screenFrame.midX, y: geometry.screenFrame.maxY)
        let trigger = geometry.hoverRect(for: .collapsed)

        XCTAssertFalse(trigger.contains(topRow), "documents why `contains` cannot be used")
        XCTAssertTrue(NotchGeometry.pointer(topRow, isIn: trigger))
        XCTAssertTrue(NotchGeometry.pointer(topRow, isIn: geometry.screenFrame))
    }

    func testThePanelsBottomEdgeIsStillOutside() {
        let rect = geometry.hoverRect(for: .collapsed)
        let below = CGPoint(x: rect.midX, y: rect.minY)
        XCTAssertFalse(NotchGeometry.pointer(below, isIn: rect))
    }

    func testClicksOnTheTopRowHitTheNotch() {
        let hit = geometry.hitRect(for: .collapsed)
        let topRow = CGPoint(x: hit.midX, y: geometry.windowSize.height)
        XCTAssertTrue(NotchGeometry.pointer(topRow, isIn: hit))
    }
}

// MARK: - Peek wings

/// Every peek is drawn as two wings either side of the camera housing. Content
/// that needs more than its wing used to spill under the hardware notch.
final class PeekWingTests: XCTestCase {

    private let geometry = NotchGeometry(
        notchSize: CGSize(width: 185, height: 32),
        hasHardwareNotch: true,
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
    )

    /// Usable width in a wing after `PeekView`'s 10pt outer and 4pt inner
    /// padding.
    private func usableWing(_ content: PeekContent) -> CGFloat {
        let width = geometry.contentSize(for: .peek, peek: content).width
        return geometry.peekWingWidth(forPeekWidth: width) - 14
    }

    func testTheVolumeMeterFitsBesideTheNotch() {
        // 60pt rail, 6pt gap, 36pt value.
        XCTAssertGreaterThanOrEqual(usableWing(.systemHUD), 102)
    }

    func testABannerLineFitsBesideTheNotch() {
        XCTAssertGreaterThanOrEqual(usableWing(.banner), 136)
    }

    func testLiveAndMeetingTextFitBesideTheNotch() {
        XCTAssertGreaterThanOrEqual(usableWing(.live), 116)
        XCTAssertGreaterThanOrEqual(usableWing(.meeting), 116)
    }

    func testWingsAreSymmetricAboutTheNotch() {
        for content in [PeekContent.media, .banner, .systemHUD, .live, .agent(agents: 3)] {
            let width = geometry.contentSize(for: .peek, peek: content).width
            let wing = geometry.peekWingWidth(forPeekWidth: width)
            XCTAssertEqual(wing * 2 + geometry.notchSize.width, width, accuracy: 0.001)
        }
    }
}

// MARK: - Settings change notifications

@MainActor
final class SettingsChangeOrderingTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "com.bondex.notch.tests.settings-order.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    /// `$preferences` fires from `willSet`. Services that reacted by reading
    /// the store back saw the old value, so every widget toggle applied one
    /// change late. `preferencesDidChange` must fire once the value is stored.
    func testPreferencesDidChangeSeesTheStoredValue() {
        let store = SettingsStore(defaults: defaults)
        var observed: [Bool] = []
        let subscription = store.preferencesDidChange.sink { _ in
            observed.append(store.isTabEnabled(.clipboard))
        }
        defer { subscription.cancel() }

        store.preferences.clipboardHistoryEnabled = false
        store.preferences.clipboardHistoryEnabled = true

        XCTAssertEqual(observed, [false, true])
    }

    func testAnUnchangedWriteDoesNotNotify() {
        let store = SettingsStore(defaults: defaults)
        var count = 0
        let subscription = store.preferencesDidChange.sink { _ in count += 1 }
        defer { subscription.cancel() }

        store.preferences.clipboardHistoryEnabled = store.preferences.clipboardHistoryEnabled
        XCTAssertEqual(count, 0)
    }

    /// Switching to a profile from the palette used to wait for the next
    /// minute's timer, because the refresh read the old mode.
    func testActivatingAProfileAppliesImmediately() throws {
        let store = SettingsStore(defaults: defaults)
        let profiles = SmartProfileService(settings: store)
        profiles.start()
        defer { profiles.stop() }

        let work = try XCTUnwrap(store.preferences.notchProfiles.first { $0.name == "Work" })
        profiles.activate(work.id)

        XCTAssertEqual(store.activeProfile?.id, work.id)
    }

    /// Reordering in Settings while a profile is active must edit the standard
    /// order, not paste the profile's subset over it.
    func testTheStandardOrderIgnoresTheActiveProfile() throws {
        let store = SettingsStore(defaults: defaults)
        let work = try XCTUnwrap(store.preferences.notchProfiles.first { $0.name == "Work" })
        store.setActiveProfile(work)

        XCTAssertEqual(Set(store.standardOrderedTabs), Set(NotchTab.allCases))
        XCTAssertNotEqual(store.orderedTabs, store.standardOrderedTabs)
    }
}

// MARK: - Panel interaction

@MainActor
final class PanelInteractionTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "com.bondex.notch.tests.panel.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(closeDelay: Double = 0) throws -> NotchViewModel {
        let store = SettingsStore(defaults: defaults)
        store.preferences.closeDelay = closeDelay
        return NotchViewModel(
            settings: store,
            events: EventCenter(),
            screen: try XCTUnwrap(NSScreen.main)
        )
    }

    /// Any click that missed a control used to toggle the panel shut.
    func testClickingInsideTheOpenPanelKeepsItOpen() throws {
        let notch = try model()
        notch.panelTapped()
        XCTAssertEqual(notch.state, .expanded)

        notch.panelTapped()
        XCTAssertEqual(notch.state, .expanded)
    }

    func testAClickOutsideClosesThePanel() throws {
        let notch = try model()
        notch.panelTapped()
        notch.clickedOutside()
        XCTAssertNotEqual(notch.state, .expanded)
    }

    /// Typing in Quick Capture must survive the pointer drifting off the panel.
    func testKeyboardFocusHoldsTheHoveredPanelOpen() async throws {
        let notch = try model(closeDelay: 0)
        notch.expand()
        notch.setHoldsOpenForKeyboard(true)

        notch.pointerMoved(to: CGPoint(x: notch.geometry.screenFrame.midX, y: 10))
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(notch.state, .expanded)

        notch.setHoldsOpenForKeyboard(false)
        notch.pointerMoved(to: CGPoint(x: notch.geometry.screenFrame.midX, y: 12))
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNotEqual(notch.state, .expanded)
    }

    /// The meeting service also runs for Smart Profiles. With "Upcoming
    /// meetings" off, a meeting must not take over a peek open for playback.
    func testADisabledMeetingDoesNotTakeOverThePeek() throws {
        let notch = try model()
        notch.hasLiveActivity = true
        notch.hasUpcomingMeeting = true

        XCTAssertEqual(notch.peekContent, .media)
        XCTAssertEqual(notch.state, .peek)
    }
}

// MARK: - Downloads

@MainActor
final class FileActivityRegressionTests: XCTestCase {

    private var directory: URL!
    private var events: EventCenter!
    private var service: FileActivityService!

    override func setUp() async throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bondex-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        events = EventCenter()
        service = FileActivityService(events: events)
    }

    override func tearDown() async throws {
        service.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ name: String, bytes: Int = 64) throws {
        try Data(repeating: 0x41, count: bytes).write(to: directory.appendingPathComponent(name))
    }

    private func settle() async throws {
        try await Task.sleep(nanoseconds: 250_000_000)
    }

    /// Every preference change calls `start()` again; it used to re-take the
    /// baseline and empty the Files tab.
    func testStartingAgainKeepsReportedTransfers() async throws {
        service.start(directory: directory)
        try await settle()
        try write("report.pdf")
        try await settle()
        XCTAssertEqual(service.activities.count, 1)

        service.start(directory: directory)
        try await settle()
        XCTAssertEqual(service.activities.count, 1)
    }

    /// Cleared transfers came back on the next directory change, each posting
    /// another "Download complete" banner.
    func testClearedTransfersStayClearedAndAreNotReannounced() async throws {
        service.start(directory: directory)
        try await settle()
        try write("one.zip")
        try await settle()
        service.clearFinished()
        XCTAssertTrue(service.activities.isEmpty)

        try write("two.zip")
        try await settle()

        XCTAssertEqual(service.activities.map(\.displayName), ["two.zip"])
        XCTAssertEqual(events.events.filter { $0.title == "one.zip" }.count, 1)
    }

    /// Transfers past the visible cap were treated as new on every scan.
    func testTransfersPastTheVisibleLimitAreAnnouncedOnce() async throws {
        service.start(directory: directory)
        try await settle()
        let count = FileActivityService.visibleLimit + 3
        for index in 0..<count {
            try write("file-\(index).bin")
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await settle()
        try write("trigger.bin")
        try await settle()

        let downloads = events.events.filter { $0.kind == .download }
        XCTAssertEqual(downloads.count, count + 1)
        XCTAssertEqual(service.activities.count, FileActivityService.visibleLimit)
    }

    /// Safari downloads into a `.download` package — a folder.
    func testASafariDownloadPackageIsShownInFlight() async throws {
        service.start(directory: directory)
        try await settle()

        let package = directory.appendingPathComponent("Movie.mov.download")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4_096).write(to: package.appendingPathComponent("Movie.mov"))
        try await settle()

        let activity = try XCTUnwrap(service.activities.first)
        XCTAssertFalse(activity.isComplete)
        XCTAssertEqual(activity.displayName, "Movie.mov")
        XCTAssertEqual(activity.byteCount, 4_096)
    }
}

// MARK: - Small pure fixes

final class AuditPureFunctionTests: XCTestCase {

    /// 32-bit interface counters wrap, and the sum drops when an interface
    /// goes away. The wrapping subtraction produced ~2^64 bytes/s, which the
    /// System tab then converted to Int64 and crashed on.
    func testANetworkCounterDropIsNotAHugeRate() {
        XCTAssertEqual(SystemMetricsService.networkRate(from: 5_000, to: 1_000, over: 2), 0)
        XCTAssertEqual(SystemMetricsService.networkRate(from: 1_000, to: 5_000, over: 2), 2_000)
        XCTAssertEqual(SystemMetricsService.networkRate(from: 1_000, to: 5_000, over: 0), 0)
    }

    /// Office and iWork add a picture of copied text; that copy is text.
    func testCopiedTextWithACourtesyPictureStaysText() {
        XCTAssertFalse(ClipboardHistoryService.prefersImage(in: [.string, .rtf, .tiff]))
        XCTAssertTrue(ClipboardHistoryService.prefersImage(in: [.png, .string]))
        XCTAssertTrue(ClipboardHistoryService.prefersImage(in: [.tiff]))
        XCTAssertFalse(ClipboardHistoryService.prefersImage(in: [.string]))
    }

    /// A long block already under way must not hide the next meeting.
    func testTheNextMeetingBeatsALongBlockAlreadyUnderWay() {
        let now = Date()
        let events = [
            (start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(7_200)),
            (start: now.addingTimeInterval(300), end: now.addingTimeInterval(2_100))
        ]
        XCTAssertEqual(UpcomingMeetingService.preferredEvent(in: events, now: now), 1)
    }

    func testAMeetingThatJustStartedIsStillPreferred() {
        let now = Date()
        let events = [
            (start: now.addingTimeInterval(-120), end: now.addingTimeInterval(1_800)),
            (start: now.addingTimeInterval(900), end: now.addingTimeInterval(2_700))
        ]
        XCTAssertEqual(UpcomingMeetingService.preferredEvent(in: events, now: now), 0)
    }

    func testAnInProgressEventIsShownWhenNothingElseIsComing() {
        let now = Date()
        let events = [(start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(600))]
        XCTAssertEqual(UpcomingMeetingService.preferredEvent(in: events, now: now), 0)
    }

    /// Every media script must check the app is running before talking to it,
    /// or a poll relaunches an app the user just quit.
    func testMediaScriptsDoNotLaunchTheirApp() {
        let script = MediaApp.music.onlyWhileRunning("tell application \"Music\" to playpause")
        XCTAssertTrue(script.hasPrefix("if application id \"com.apple.Music\" is running then"))
        XCTAssertTrue(script.hasSuffix("end if"))
    }

    func testCodexAsyncInputRequestReadsAsWaiting() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PreToolUse",
            "tool_name": "request_user_input_async",
            "tool_input": [:]
        ])
        XCTAssertEqual(
            AgentHookInput.action(from: data),
            .attention(message: "Waiting for your input")
        )
    }
}

// MARK: - Focus timer

@MainActor
final class FocusTimerRegressionTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "com.bondex.notch.tests.focus-audit.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    /// Quitting used to cancel the timer, erasing the end date the next launch
    /// restores from.
    func testShuttingDownKeepsTheSessionForTheNextLaunch() {
        let original = FocusTimerService(defaults: defaults, events: EventCenter())
        original.start(minutes: 25)
        original.suspend()

        let relaunched = FocusTimerService(defaults: defaults, events: EventCenter())
        XCTAssertTrue(relaunched.snapshot.isRunning)
        relaunched.cancel()
    }

    func testDisablingTheTimerEndsARunningSession() {
        let timer = FocusTimerService(defaults: defaults, events: EventCenter())
        timer.start(minutes: 25)
        timer.isEnabled = false
        XCTAssertFalse(timer.snapshot.isActive)
    }
}

// MARK: - UI polish

final class PlaybackPublishingTests: XCTestCase {

    private func sample(
        title: String = "Blinding Lights",
        isPlaying: Bool = true,
        position: TimeInterval,
        at date: Date
    ) -> NowPlaying {
        NowPlaying(
            source: .spotify,
            title: title,
            artist: "The Weeknd",
            album: "After Hours",
            isPlaying: isPlaying,
            duration: 200,
            position: position,
            artwork: nil,
            sampledAt: date
        )
    }

    /// A poll a second later, a second further on, changes nothing anyone can
    /// see, and must not redraw the panel.
    func testPlaybackMovingOnIsNotANewSample() {
        let start = Date()
        let first = sample(position: 78, at: start)
        let next = sample(position: 79.1, at: start.addingTimeInterval(1))
        XCTAssertTrue(first.continues(as: next))
    }

    func testASeekIsANewSample() {
        let start = Date()
        let first = sample(position: 78, at: start)
        XCTAssertFalse(first.continues(as: sample(position: 140, at: start.addingTimeInterval(1))))
    }

    func testPausingIsANewSample() {
        let start = Date()
        let first = sample(position: 78, at: start)
        XCTAssertFalse(first.continues(
            as: sample(isPlaying: false, position: 79, at: start.addingTimeInterval(1))
        ))
    }

    func testAnotherTrackIsANewSample() {
        let start = Date()
        let first = sample(position: 78, at: start)
        XCTAssertFalse(first.continues(
            as: sample(title: "Save Your Tears", position: 0, at: start.addingTimeInterval(1))
        ))
    }
}

@MainActor
final class TabPolishTests: XCTestCase {

    /// New installs start with the everyday set; the rest are a toggle away.
    func testNewInstallsStartWithTheEverydayTabs() throws {
        let suite = "com.bondex.notch.tests.default-tabs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)

        let enabled = store.orderedTabs.filter(store.isTabEnabled)
        XCTAssertEqual(enabled, [.home, .agents, .capture, .music, .clipboard, .shelf])
    }

    /// Someone who already chose their tabs keeps them: stored values win over
    /// the new defaults.
    func testExistingChoicesSurviveTheNewDefaults() throws {
        let stored = #"{"systemWidgetEnabled":true,"activityFeedEnabled":true}"#
        let decoded = try XCTUnwrap(SettingsStore.decode(Data(stored.utf8)))
        XCTAssertTrue(decoded.systemWidgetEnabled)
        XCTAssertTrue(decoded.activityFeedEnabled)
        XCTAssertFalse(decoded.fileActivityEnabled)
    }

    func testTabChangesKnowWhichWayTheyMove() throws {
        let suite = "com.bondex.notch.tests.tab-direction.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let notch = NotchViewModel(
            settings: SettingsStore(defaults: defaults),
            events: EventCenter(),
            screen: try XCTUnwrap(NSScreen.main)
        )
        notch.tabOrder = [.home, .capture, .music, .clipboard]

        notch.tab = .music
        XCTAssertTrue(notch.tabAdvances)
        notch.tab = .capture
        XCTAssertFalse(notch.tabAdvances)
    }
}
