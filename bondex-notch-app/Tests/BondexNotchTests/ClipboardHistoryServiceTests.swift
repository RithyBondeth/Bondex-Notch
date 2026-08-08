import AppKit
import XCTest
@testable import BondexNotch

@MainActor
final class ClipboardHistoryServiceTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("BondexClipboardTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() async throws {
        pasteboard.clearContents()
        pasteboard = nil
    }

    func testCapturesTextAndSuppressesDuplicates() throws {
        let service = ClipboardHistoryService(pasteboard: pasteboard)

        writeText("First note")
        service.captureIfChanged()
        let originalID = try XCTUnwrap(service.items.first?.id)

        writeText("First note")
        service.captureIfChanged()

        XCTAssertEqual(service.items.count, 1)
        XCTAssertEqual(service.items.first?.id, originalID)
        XCTAssertEqual(service.items.first?.title, "First note")
    }

    func testPauseSkipsCopiesMadeWhilePaused() {
        let service = ClipboardHistoryService(pasteboard: pasteboard)
        service.setPaused(true)

        writeText("Private while paused")
        service.captureIfChanged()
        service.setPaused(false)
        service.captureIfChanged()

        XCTAssertTrue(service.items.isEmpty)
    }

    func testConcealedPasswordManagerEntryIsIgnored() {
        let service = ClipboardHistoryService(pasteboard: pasteboard)
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

        pasteboard.declareTypes([.string, concealed], owner: nil)
        pasteboard.setString("not-for-history", forType: .string)
        pasteboard.setData(Data(), forType: concealed)
        service.captureIfChanged()

        XCTAssertTrue(service.items.isEmpty)
    }

    func testImageCanBeCapturedAndCopiedBack() throws {
        let service = ClipboardHistoryService(pasteboard: pasteboard)
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])

        pasteboard.clearContents()
        pasteboard.setData(imageData, forType: .png)
        service.captureIfChanged()
        let item = try XCTUnwrap(service.items.first)

        XCTAssertEqual(item.content, .image(data: imageData, type: .png))
        service.copy(item)
        XCTAssertEqual(pasteboard.data(forType: .png), imageData)
        service.captureIfChanged()
        XCTAssertEqual(service.items.count, 1, "Copying from history must not recapture itself")
    }

    func testPinnedItemsStayAboveNewItemsAndCapacityIsBounded() throws {
        let service = ClipboardHistoryService(pasteboard: pasteboard, capacity: 2)

        writeText("Pinned")
        service.captureIfChanged()
        service.togglePinned(try XCTUnwrap(service.items.first))

        for value in ["Second", "Third"] {
            writeText(value)
            service.captureIfChanged()
        }

        XCTAssertEqual(service.items.count, 2)
        XCTAssertEqual(service.items.first?.title, "Pinned")
        XCTAssertTrue(service.items.first?.isPinned == true)
        XCTAssertEqual(service.items.last?.title, "Third")
    }

    func testSearchMatchesTextAndLinkMetadata() {
        let text = ClipboardHistoryItem(content: .text("Project launch notes"))
        let link = ClipboardHistoryItem(content: .text("https://example.com/docs"))

        XCTAssertTrue(text.matches("LAUNCH"))
        XCTAssertTrue(link.matches("link"))
        XCTAssertFalse(text.matches("invoice"))
    }

    private func writeText(_ value: String) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
