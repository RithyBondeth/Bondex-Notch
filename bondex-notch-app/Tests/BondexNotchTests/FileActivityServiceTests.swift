import XCTest
@testable import BondexNotch

/// Directory watching is the easiest thing here to get subtly wrong — the
/// baseline, the partial-download suffixes, and the completion event all have
/// to line up — so it gets real coverage against a temporary directory.
@MainActor
final class FileActivityServiceTests: XCTestCase {

    private var directory: URL!
    private var events: EventCenter!
    private var service: FileActivityService!

    override func setUp() async throws {
        try await super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bondex-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        events = EventCenter()
        service = FileActivityService(events: events)
    }

    override func tearDown() async throws {
        service.stop()
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    func testFilesPresentBeforeWatchingAreNotReportedAsActivity() async throws {
        try write("already-here.txt", bytes: 128)

        service.start(directory: directory)
        try await settle()

        XCTAssertTrue(service.activities.isEmpty)
        XCTAssertTrue(events.events.isEmpty)
    }

    func testNewFileIsReportedAndPostsACompletionEvent() async throws {
        service.start(directory: directory)
        try await settle()

        try write("report.pdf", bytes: 2_048)
        try await settle()

        XCTAssertEqual(service.activities.count, 1)
        let activity = try XCTUnwrap(service.activities.first)
        XCTAssertEqual(activity.displayName, "report.pdf")
        XCTAssertEqual(activity.byteCount, 2_048)
        XCTAssertTrue(activity.isComplete)

        XCTAssertEqual(events.events.count, 1)
        XCTAssertEqual(events.events.first?.kind, .download)
        XCTAssertEqual(events.events.first?.title, "report.pdf")
    }

    func testPartialDownloadIsInFlightAndItsFinalNameIsUsed() async throws {
        service.start(directory: directory)
        try await settle()

        try write("installer.dmg.crdownload", bytes: 512)
        try await settle()

        let activity = try XCTUnwrap(service.activities.first)
        XCTAssertFalse(activity.isComplete, "A .crdownload sidecar is still transferring")
        XCTAssertEqual(activity.displayName, "installer.dmg",
                       "The sidecar suffix should not leak into the UI")
        XCTAssertTrue(events.events.isEmpty, "An unfinished transfer is not a completion")
    }

    func testInFlightTransferBecomesCompleteWhenRenamed() async throws {
        service.start(directory: directory)
        try await settle()

        try write("installer.dmg.crdownload", bytes: 512)
        try await settle()
        XCTAssertEqual(service.activities.filter { !$0.isComplete }.count, 1)

        try FileManager.default.moveItem(
            at: directory.appendingPathComponent("installer.dmg.crdownload"),
            to: directory.appendingPathComponent("installer.dmg")
        )
        try await settle()

        XCTAssertEqual(service.activities.count, 1)
        let activity = try XCTUnwrap(service.activities.first)
        XCTAssertTrue(activity.isComplete)
        XCTAssertEqual(activity.displayName, "installer.dmg")
        XCTAssertEqual(events.events.first?.kind, .download)
    }

    func testDirectoriesAreIgnored() async throws {
        service.start(directory: directory)
        try await settle()

        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("a-folder"),
            withIntermediateDirectories: true
        )
        try await settle()

        XCTAssertTrue(service.activities.isEmpty)
    }

    // MARK: Helpers

    private func write(_ name: String, bytes: Int) throws {
        try Data(repeating: 0x41, count: bytes)
            .write(to: directory.appendingPathComponent(name))
    }

    /// The service reacts to a dispatch source on the main queue; give it a
    /// turn of the run loop before asserting.
    private func settle() async throws {
        try await Task.sleep(nanoseconds: 250_000_000)
    }
}
