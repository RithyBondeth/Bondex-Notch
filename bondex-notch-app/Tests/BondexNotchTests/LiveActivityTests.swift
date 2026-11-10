import Foundation
import XCTest
@testable import BondexNotch

final class LiveActivityCommandTests: XCTestCase {
    func testStartParsesNamedFields() {
        XCTAssertEqual(
            LiveActivityCommand.parse([
                "BondexNotch", "--live-start", "release-build",
                "--title", "Building release",
                "--subtitle", "Compiling Swift",
                "--progress", "0.25"
            ]),
            .command(.start(
                id: "release-build",
                title: "Building release",
                subtitle: "Compiling Swift",
                progress: 0.25
            ))
        )
    }

    func testUpdateCanChangeOnlyProgress() {
        XCTAssertEqual(
            LiveActivityCommand.parse([
                "BondexNotch", "--live-update", "release-build", "--progress", "0.8"
            ]),
            .command(.update(
                id: "release-build", title: nil, subtitle: nil, progress: 0.8
            ))
        )
    }

    func testFinishCarriesAMessage() {
        XCTAssertEqual(
            LiveActivityCommand.parse([
                "BondexNotch", "--live-finish", "release-build",
                "--message", "Build succeeded"
            ]),
            .command(.finish(id: "release-build", message: "Build succeeded"))
        )
    }

    func testProgressOutsideTheUnitIntervalIsRejected() {
        guard case .invalid(_, let message) = LiveActivityCommand.parse([
            "BondexNotch", "--live-start", "build",
            "--title", "Build", "--progress", "72"
        ]) else { return XCTFail("Expected invalid progress") }
        XCTAssertTrue(message.contains("between 0 and 1"))
    }

    func testIDsCannotEscapeTheSignalDirectory() {
        guard case .invalid = LiveActivityCommand.parse([
            "BondexNotch", "--live-start", "../../../tmp", "--title", "Bad"
        ]) else { return XCTFail("Expected invalid id") }
    }

    func testUnrelatedArgumentsStartTheAppNormally() {
        XCTAssertEqual(LiveActivityCommand.parse(["BondexNotch", "--render-previews"]), .none)
    }
}

final class LiveActivitySignalTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bondex-live-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testStartUpdateAndFinishRoundTrip() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try LiveActivityService.startActivity(
            id: "build",
            title: "Building release",
            subtitle: "Compiling",
            progress: 0.1,
            directory: directory
        )
        let started = try XCTUnwrap(LiveActivityService.read(id: "build", directory: directory))
        XCTAssertEqual(started.state, .active)
        XCTAssertEqual(started.progress, 0.1)

        try LiveActivityService.updateActivity(
            id: "build",
            title: nil,
            subtitle: "Running tests",
            progress: 0.75,
            directory: directory
        )
        let updated = try XCTUnwrap(LiveActivityService.read(id: "build", directory: directory))
        XCTAssertEqual(updated.title, "Building release")
        XCTAssertEqual(updated.subtitle, "Running tests")
        XCTAssertEqual(updated.progress, 0.75)
        XCTAssertEqual(updated.startedAt, started.startedAt)

        try LiveActivityService.finishActivity(
            id: "build", message: "Build succeeded", directory: directory
        )
        let finished = try XCTUnwrap(LiveActivityService.read(id: "build", directory: directory))
        XCTAssertEqual(finished.state, .finished)
        XCTAssertEqual(finished.completionMessage, "Build succeeded")
    }

    func testUpdatingAMissingActivityFails() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try LiveActivityService.updateActivity(
            id: "missing",
            title: nil,
            subtitle: "Still working",
            progress: nil,
            directory: directory
        ))
    }

    func testDirectoryListingIgnoresUnrelatedFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data().write(to: directory.appendingPathComponent("notes.txt"))
        try Data().write(to: directory.appendingPathComponent("not valid.json"))
        try LiveActivityService.startActivity(
            id: "export", title: "Exporting", subtitle: nil, progress: nil,
            directory: directory
        )

        XCTAssertEqual(
            LiveActivityService.signalURLs(directory: directory).map(\.lastPathComponent),
            ["export.json"]
        )
    }
}
