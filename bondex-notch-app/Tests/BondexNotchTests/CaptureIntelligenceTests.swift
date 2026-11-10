import XCTest
@testable import BondexNotch

final class CaptureEnhancementTests: XCTestCase {
    func testNormalizationBoundsAndDeduplicatesGeneratedContent() {
        let result = CaptureEnhancement(
            title: String(repeating: "T", count: 100),
            summary: String(repeating: "S", count: 300),
            actionItems: [" Ship ", "ship", "Review", "Test", "Publish"],
            tags: [" Swift ", "swift", "macOS", "AI", "extra"]
        ).normalized(fallbackText: "Fallback")

        XCTAssertEqual(result.title.count, 80)
        XCTAssertEqual(result.summary.count, 240)
        XCTAssertEqual(result.actionItems, ["Ship", "Review", "Test", "Publish"])
        XCTAssertEqual(result.tags, ["Swift", "macOS", "AI"])
    }

    func testBlankGeneratedTitleFallsBackToCaptureText() {
        let result = CaptureEnhancement(
            title: "  ",
            summary: "",
            actionItems: [],
            tags: []
        ).normalized(fallbackText: "  Keep   the meaning \n intact ")

        XCTAssertEqual(result.title, "Keep the meaning intact")
    }
}

@MainActor
final class CaptureIntelligenceServiceTests: XCTestCase {
    func testUnavailableModelNeverCallsEnhancementProvider() async {
        let called = LockedFlag()
        let service = CaptureIntelligenceService(
            availabilityProvider: { .unavailable("Not available") },
            enhancementProvider: { _ in
                called.set()
                return CaptureEnhancement(title: "", summary: "", actionItems: [], tags: [])
            }
        )

        let result = await service.enhance("A note")

        XCTAssertNil(result)
        XCTAssertFalse(called.value)
        XCTAssertEqual(service.errorMessage, "Not available")
    }

    func testEnhancementProviderResultIsNormalized() async {
        let service = CaptureIntelligenceService(
            availabilityProvider: { .available },
            enhancementProvider: { _ in
                CaptureEnhancement(
                    title: "  Plan launch  ",
                    summary: "  Coordinate the launch.  ",
                    actionItems: [" Ship build "],
                    tags: [" release "]
                )
            }
        )

        let result = await service.enhance("Coordinate the launch")

        XCTAssertEqual(result?.title, "Plan launch")
        XCTAssertEqual(result?.summary, "Coordinate the launch.")
        XCTAssertEqual(result?.actionItems, ["Ship build"])
        XCTAssertEqual(result?.tags, ["release"])
        XCTAssertFalse(service.isEnhancing)
        XCTAssertNil(service.errorMessage)
    }

    func testEmptyInputIsRejectedBeforeCallingModel() async {
        let service = CaptureIntelligenceService(
            availabilityProvider: { .available },
            enhancementProvider: { _ in
                XCTFail("Model should not run")
                return CaptureEnhancement(title: "", summary: "", actionItems: [], tags: [])
            }
        )

        let result = await service.enhance(" \n ")
        XCTAssertNil(result)
        XCTAssertEqual(service.errorMessage, "Enter something before enhancing it.")
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool { lock.withLock { storage } }
    func set() { lock.withLock { storage = true } }
}
