import Sparkle
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

    // MARK: The settings a release ships

    private var resources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
    }

    /// Starts Sparkle's real updater on a stand-in app carrying exactly what
    /// build-app.sh merges into an updatable build.
    @MainActor
    private func startUpdater(adjusting adjust: (inout [String: Any]) -> Void = { _ in }) throws {
        let identifier = "com.bondex.notch.tests.updater.\(UUID().uuidString)"
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(identifier).app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: app)
            UserDefaults.standard.removePersistentDomain(forName: identifier)
        }

        var info = try XCTUnwrap(
            NSDictionary(contentsOf: resources.appendingPathComponent("SparkleInfo.plist")) as? [String: Any]
        )
        info["SUPublicEDKey"] = try String(
            contentsOf: resources.appendingPathComponent("SparklePublicKey.txt"), encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        info["CFBundleIdentifier"] = identifier
        info["CFBundleName"] = "Bondex Notch"
        info["CFBundleExecutable"] = "BondexNotch"
        info["CFBundlePackageType"] = "APPL"
        info["CFBundleVersion"] = "1.0.0"
        info["CFBundleShortVersionString"] = "1.0.0"
        adjust(&info)
        XCTAssertTrue((info as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true))
        FileManager.default.createFile(atPath: app.appendingPathComponent("Contents/MacOS/BondexNotch").path, contents: Data())

        let bundle = try XCTUnwrap(Bundle(url: app))
        XCTAssertTrue(UpdateService.isConfigured(bundle.infoDictionary ?? [:]))
        let updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: SPUStandardUserDriver(hostBundle: bundle, delegate: nil),
            delegate: nil
        )
        try updater.start()
    }

    /// 1.1.0 shipped settings Sparkle refuses at start, so it never checked.
    @MainActor
    func testTheShippedUpdateSettingsLetSparkleStart() throws {
        XCTAssertNoThrow(try startUpdater())
    }

    /// The same check catches 1.1.0's mistake.
    @MainActor
    func testASignedFeedWithoutVerificationBeforeExtractionIsRefused() {
        XCTAssertThrowsError(try startUpdater { $0["SUVerifyUpdateBeforeExtraction"] = nil })
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
