import XCTest
@testable import BondexNotch

/// When a copy of the app may update itself.
final class UpdateServiceTests: XCTestCase {

    private let feed = "https://github.com/RithyBondeth/Bondex-Notch/releases/latest/download/appcast.xml"
    private let key = "tA4M9LZuNgUmSoOBadKLVDmbpLjVsyNO/Uj3ppqvMG8="

    func testAReleaseWithAFeedAndAKeyUpdates() {
        XCTAssertTrue(UpdateService.isConfigured(["SUFeedURL": feed, "SUPublicEDKey": key]))
    }

    /// A developer's own build carries neither, and must never replace itself
    /// with a release.
    func testABuildWithoutThemDoesNot() {
        XCTAssertFalse(UpdateService.isConfigured([:]))
        XCTAssertFalse(UpdateService.isConfigured(["SUFeedURL": feed]))
        XCTAssertFalse(UpdateService.isConfigured(["SUPublicEDKey": key]))
        XCTAssertFalse(UpdateService.isConfigured(["SUFeedURL": feed, "SUPublicEDKey": "  "]))
    }

    func testAFeedOverPlainHTTPIsRefused() {
        XCTAssertFalse(UpdateService.isConfigured([
            "SUFeedURL": "http://github.com/appcast.xml",
            "SUPublicEDKey": key
        ]))
    }

    @MainActor
    func testTheTestHostIsNotAnUpdatableBuild() {
        let service = UpdateService()
        XCTAssertFalse(service.isConfigured)
        // Starting an unconfigured service does nothing, rather than asking.
        service.start()
        XCTAssertFalse(service.canCheck)
    }
}
