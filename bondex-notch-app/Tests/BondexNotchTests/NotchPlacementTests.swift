import AppKit
import XCTest
@testable import BondexNotch

/// Which display the notch belongs on, with a laptop and an external monitor
/// arranged side by side.
final class NotchPlacementTests: XCTestCase {

    private let laptop = NotchPlacement.Display(
        id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), isBuiltIn: true
    )
    private let monitor = NotchPlacement.Display(
        id: 3, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), isBuiltIn: false
    )
    private var both: [NotchPlacement.Display] { [laptop, monitor] }

    func testFollowingGoesToTheDisplayWithThePointer() {
        let onMonitor = CGPoint(x: 2400, y: 500)
        XCTAssertEqual(
            NotchPlacement.target(for: .followPointer, among: both, pointer: onMonitor, main: laptop),
            monitor
        )
        let onLaptop = CGPoint(x: 700, y: 500)
        XCTAssertEqual(
            NotchPlacement.target(for: .followPointer, among: both, pointer: onLaptop, main: monitor),
            laptop
        )
    }

    /// The top row of a display is where a pointer thrown at its notch lands;
    /// it must count as that display.
    func testThePointerOnTheTopRowCountsAsThatDisplay() {
        let topRow = CGPoint(x: 2400, y: monitor.frame.maxY)
        XCTAssertEqual(
            NotchPlacement.target(for: .followPointer, among: both, pointer: topRow, main: laptop),
            monitor
        )
    }

    func testBuiltInStaysPutWhereverThePointerIs() {
        let onMonitor = CGPoint(x: 2400, y: 500)
        XCTAssertEqual(
            NotchPlacement.target(for: .builtIn, among: both, pointer: onMonitor, main: monitor),
            laptop
        )
    }

    /// Lid closed: "built-in" falls back to the main display; "built-in only"
    /// hides the notch.
    func testAClosedLidFallsBackOrHides() {
        XCTAssertEqual(
            NotchPlacement.target(for: .builtIn, among: [monitor], pointer: nil, main: monitor),
            monitor
        )
        XCTAssertNil(
            NotchPlacement.target(for: .builtInOnly, among: [monitor], pointer: nil, main: monitor)
        )
    }

    /// Someone who had switched external displays off keeps the notch on the
    /// built-in display; everyone else gets it where they are working.
    func testTheOldSwitchMigrates() throws {
        let off = try XCTUnwrap(SettingsStore.decode(Data(#"{"showNotchOnExternalDisplays":false}"#.utf8)))
        XCTAssertEqual(off.notchDisplay, .builtInOnly)

        let on = try XCTUnwrap(SettingsStore.decode(Data(#"{"showNotchOnExternalDisplays":true}"#.utf8)))
        XCTAssertEqual(on.notchDisplay, .followPointer)

        let chosen = try XCTUnwrap(SettingsStore.decode(Data(
            #"{"showNotchOnExternalDisplays":false,"notchDisplay":"builtIn"}"#.utf8
        )))
        XCTAssertEqual(chosen.notchDisplay, .builtIn, "an explicit choice wins over the old switch")
    }

    /// A monitor above the laptop has its origin far from y = 0; the menu bar is
    /// still the strip at its top.
    func testTheStandInNotchMatchesTheMenuBarOnADisplayAboveTheLaptop() {
        let frame = CGRect(x: -147, y: 982, width: 1920, height: 1080)
        let visible = CGRect(x: -147, y: 982, width: 1920, height: 1080 - 30)
        XCTAssertEqual(NotchGeometry.syntheticNotchHeight(frame: frame, visibleFrame: visible), 30)
    }

    func testTheStandInNotchKeepsItsBoundsWhenTheMenuBarHides() {
        let frame = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(NotchGeometry.syntheticNotchHeight(frame: frame, visibleFrame: frame), 24)
    }
}
