import AppKit
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import BondexNotch

@MainActor
final class ShelfServiceTests: XCTestCase {

    private var sourceURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Bondex-Shelf-Test-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)
    }

    override func tearDownWithError() throws {
        if let sourceURL { try? FileManager.default.removeItem(at: sourceURL) }
        sourceURL = nil
        try super.tearDownWithError()
    }

    func testFinderFileURLResolvesWithoutCopying() async throws {
        let service = ShelfService(events: EventCenter())
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: sourceURL))

        let urls = await service.resolve(providers: [provider])

        XCTAssertEqual(urls, [sourceURL])
        XCTAssertFalse(ShelfService.isShelfCopy(try XCTUnwrap(urls.first)))
    }

    func testImageOnlyScreenshotDropIsMaterializedAndCleanedUp() async throws {
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 24).fill()
        image.unlockFocus()

        let provider = NSItemProvider(object: image)
        XCTAssertFalse(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.image.identifier))

        let service = ShelfService(events: EventCenter())
        let urls = await service.resolve(providers: [provider])
        let materialized = try XCTUnwrap(urls.first)

        XCTAssertTrue(ShelfService.isShelfCopy(materialized))
        XCTAssertTrue(FileManager.default.fileExists(atPath: materialized.path))
        XCTAssertEqual(service.add(urls: urls), 1)

        service.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: materialized.path))
    }

    func testPruneMissingItemsRemovesDeletedFiles() throws {
        let service = ShelfService(events: EventCenter())
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("Bondex-Shelf-Temp-\(UUID().uuidString).txt")
        try "test".write(to: tempFile, atomically: true, encoding: .utf8)

        XCTAssertEqual(service.add(urls: [sourceURL, tempFile]), 2)
        XCTAssertFalse(service.hasMissingItems)

        // Delete the temp file to simulate an external file deletion
        try FileManager.default.removeItem(at: tempFile)
        XCTAssertTrue(service.hasMissingItems)

        service.pruneMissingItems()
        XCTAssertFalse(service.hasMissingItems)
        XCTAssertEqual(service.items.count, 1)
        XCTAssertEqual(service.items.first?.url, sourceURL)
    }
}

/// The shelf survives a restart, and follows files that move.
@MainActor
final class ShelfPersistenceTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!
    private var folder: URL!

    override func setUpWithError() throws {
        suite = "com.bondex.notch.tests.shelf.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Bondex-Shelf-Persist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("shelf".utf8).write(to: url)
        return url
    }

    func testShelvedFilesComeBackAfterARestart() throws {
        let report = try file("report.pdf")
        let notes = try file("notes.txt")
        ShelfService(events: EventCenter(), defaults: defaults).add(urls: [report, notes])

        let relaunched = ShelfService(events: EventCenter(), defaults: defaults)
        XCTAssertEqual(
            Set(relaunched.items.map(\.url.standardizedFileURL.path)),
            Set([report, notes].map(\.standardizedFileURL.path))
        )
    }

    /// The tile used to keep its original path, so a moved file was "missing"
    /// for good.
    func testAMovedFileIsFoundAtItsNewPath() throws {
        let original = try file("draft.key")
        let service = ShelfService(events: EventCenter(), defaults: defaults)
        service.add(urls: [original])

        let moved = folder.appendingPathComponent("final.key")
        try FileManager.default.moveItem(at: original, to: moved)
        XCTAssertTrue(service.hasMissingItems)

        service.refreshLocations()
        XCTAssertFalse(service.hasMissingItems)
        XCTAssertEqual(service.items.first?.url.lastPathComponent, "final.key")

        let relaunched = ShelfService(events: EventCenter(), defaults: defaults)
        XCTAssertEqual(relaunched.items.first?.url.lastPathComponent, "final.key")
    }

    func testADeletedFileIsDroppedOnRestore() throws {
        let gone = try file("gone.txt")
        let kept = try file("kept.txt")
        ShelfService(events: EventCenter(), defaults: defaults).add(urls: [gone, kept])
        try FileManager.default.removeItem(at: gone)

        let relaunched = ShelfService(events: EventCenter(), defaults: defaults)
        XCTAssertEqual(relaunched.items.map(\.url.lastPathComponent), ["kept.txt"])
    }

    /// Finder's Delete is a move to the Trash, which the bookmark would follow.
    func testAFileMovedToTheTrashIsTreatedAsGone() throws {
        let original = try file("old.txt")
        let service = ShelfService(events: EventCenter(), defaults: defaults)
        service.add(urls: [original])

        // A stand-in Trash, so the test never touches the real one.
        let trash = folder.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: trash.appendingPathComponent("old.txt"))

        service.refreshLocations()
        XCTAssertTrue(service.hasMissingItems)
        XCTAssertTrue(ShelfService(events: EventCenter(), defaults: defaults).items.isEmpty)
    }

    /// Without a store the shelf stays in memory, as tests and previews need.
    func testAShelfWithoutAStoreKeepsNothing() throws {
        ShelfService(events: EventCenter()).add(urls: [try file("a.txt")])
        XCTAssertTrue(ShelfService(events: EventCenter()).items.isEmpty)
    }
}
