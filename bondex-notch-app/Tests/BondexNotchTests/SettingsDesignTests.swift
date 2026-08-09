import XCTest
@testable import BondexNotch

final class SettingsDesignTests: XCTestCase {

    func testEverySettingsPageHasDistinctNavigationMetadata() {
        let pages = SettingsPage.allCases

        XCTAssertEqual(Set(pages.map(\.id)).count, pages.count)
        XCTAssertEqual(Set(pages.map(\.title)).count, pages.count)
        XCTAssertEqual(Set(pages.map(\.systemImage)).count, pages.count)
        XCTAssertTrue(pages.allSatisfy { !$0.subtitle.isEmpty })
    }

    func testTheSidebarIncludesEveryExistingSettingsArea() {
        XCTAssertEqual(
            SettingsPage.allCases,
            [.general, .widgets, .shortcuts, .appearance, .license, .permissions]
        )
    }
}
