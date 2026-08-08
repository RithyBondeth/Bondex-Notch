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
        XCTAssertFalse(ShelfService.isTemporaryCopy(try XCTUnwrap(urls.first)))
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

        XCTAssertTrue(ShelfService.isTemporaryCopy(materialized))
        XCTAssertTrue(FileManager.default.fileExists(atPath: materialized.path))
        XCTAssertEqual(service.add(urls: urls), 1)

        service.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: materialized.path))
    }
}
