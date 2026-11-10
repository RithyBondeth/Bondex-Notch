import AppKit
import XCTest
@testable import BondexNotch

@MainActor
final class QuickCaptureServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var pasteboard: NSPasteboard!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "com.bondex.notch.tests.capture.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        pasteboard = NSPasteboard(name: .init("BondexQuickCaptureTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        pasteboard.clearContents()
        defaults = nil
        pasteboard = nil
        suiteName = nil
    }

    func testSavingTrimsAndPersistsAcrossRestart() throws {
        let service = makeService()
        service.draft = "  Ship Quick Capture  \n"

        XCTAssertTrue(service.saveDraft())
        XCTAssertEqual(service.items.first?.text, "Ship Quick Capture")
        XCTAssertTrue(service.draft.isEmpty)

        let restored = makeService()
        XCTAssertEqual(restored.items, service.items)
    }

    func testEmptyAndOversizedDraftsAreRejected() {
        let service = makeService()
        service.draft = "  \n "
        XCTAssertFalse(service.saveDraft())

        service.draft = String(repeating: "x", count: 10_001)
        XCTAssertFalse(service.saveDraft())
        XCTAssertTrue(service.items.isEmpty)
    }

    func testDuplicateMovesToNewestWithoutCreatingAnotherItem() throws {
        let service = makeService()
        service.draft = "Keep me"
        XCTAssertTrue(service.saveDraft())
        let original = try XCTUnwrap(service.items.first)
        service.togglePinned(original)

        service.draft = "Keep me"
        XCTAssertTrue(service.saveDraft())

        XCTAssertEqual(service.items.count, 1)
        XCTAssertEqual(service.items.first?.id, original.id)
        XCTAssertTrue(service.items.first?.isPinned == true)
    }

    func testPasteAndCopyUseTheInjectedPasteboard() throws {
        let service = makeService()
        pasteboard.clearContents()
        pasteboard.setString("Selected text", forType: .string)

        XCTAssertTrue(service.pasteFromClipboard())
        XCTAssertEqual(service.draft, "Selected text")
        XCTAssertTrue(service.saveDraft())

        pasteboard.clearContents()
        service.copy(try XCTUnwrap(service.items.first))
        XCTAssertEqual(pasteboard.string(forType: .string), "Selected text")
    }

    func testPinnedCaptureSurvivesCapacityTrimming() throws {
        let service = makeService(capacity: 2)
        service.draft = "Pinned"
        XCTAssertTrue(service.saveDraft())
        service.togglePinned(try XCTUnwrap(service.items.first))

        for value in ["Second", "Third"] {
            service.draft = value
            XCTAssertTrue(service.saveDraft())
        }

        XCTAssertEqual(service.items.map(\.text), ["Pinned", "Third"])
        XCTAssertTrue(service.items.first?.isPinned == true)
    }

    func testFocusRequestIsConsumedExactlyOnce() {
        let service = makeService()
        XCTAssertFalse(service.consumeFocusRequest())

        service.begin()
        XCTAssertTrue(service.consumeFocusRequest())
        XCTAssertFalse(service.consumeFocusRequest())
    }

    func testSearchAndLinkClassification() {
        let note = QuickCaptureItem(text: "Prepare launch notes")
        let link = QuickCaptureItem(text: "https://example.com/spec")

        XCTAssertTrue(note.matches("LAUNCH"))
        XCTAssertFalse(note.matches("invoice"))
        XCTAssertTrue(link.isLink)
        XCTAssertEqual(link.detail, "Link")
    }

    func testEnhancementIsPersistedAndIncludedInSearch() throws {
        let service = makeService()
        service.draft = "Discuss the release checklist with Alex tomorrow."
        service.applyEnhancement(CaptureEnhancement(
            title: "Release checklist",
            summary: "Plan the release with Alex.",
            actionItems: ["Meet Alex tomorrow"],
            tags: ["launch", "planning"]
        ))

        XCTAssertTrue(service.saveDraft())
        let saved = try XCTUnwrap(service.items.first)
        XCTAssertEqual(saved.title, "Release checklist")
        XCTAssertEqual(saved.detail, "Plan the release with Alex.")
        XCTAssertTrue(saved.matches("planning"))
        XCTAssertEqual(makeService().items.first?.enhancement, saved.enhancement)
    }

    func testEditingDraftDropsAStaleEnhancement() {
        let service = makeService()
        service.draft = "Original"
        service.applyEnhancement(CaptureEnhancement(
            title: "Original title",
            summary: "Summary",
            actionItems: [],
            tags: []
        ))

        service.draft = "Changed"

        XCTAssertNil(service.draftEnhancement)
    }

    func testIntentCaptureDoesNotOverwriteComposerDraft() {
        let service = makeService()
        service.draft = "Still writing"

        XCTAssertTrue(service.capture("Created with Siri"))

        XCTAssertEqual(service.draft, "Still writing")
        XCTAssertEqual(service.items.first?.text, "Created with Siri")
    }

    func testGlobalHotKeyIDsRouteToSeparateActions() {
        XCTAssertEqual(GlobalHotKeyService.action(forHotKeyID: 1), .panel)
        XCTAssertEqual(GlobalHotKeyService.action(forHotKeyID: 2), .quickCapture)
        XCTAssertEqual(GlobalHotKeyService.action(forHotKeyID: 3), .commandPalette)
        XCTAssertNil(GlobalHotKeyService.action(forHotKeyID: 99))
    }

    private func makeService(capacity: Int = 100) -> QuickCaptureService {
        QuickCaptureService(defaults: defaults, pasteboard: pasteboard, capacity: capacity)
    }
}
