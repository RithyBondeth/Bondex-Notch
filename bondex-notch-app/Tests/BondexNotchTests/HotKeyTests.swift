import AppKit
import Carbon
import XCTest
@testable import BondexNotch

final class HotKeyTests: XCTestCase {

    /// Shortcuts were stored by preset name before they could be recorded;
    /// an update must keep them.
    func testShortcutsSavedAsPresetNamesStillLoad() throws {
        let stored = #"""
        {"globalShortcut":"commandShiftSpace","quickCaptureShortcut":"controlShiftSpace",
         "commandPaletteShortcut":"controlOptionReturn"}
        """#
        let preferences = try XCTUnwrap(SettingsStore.decode(Data(stored.utf8)))
        XCTAssertEqual(preferences.globalShortcut, .commandShiftSpace)
        XCTAssertEqual(preferences.quickCaptureShortcut, .controlShiftSpace)
        XCTAssertEqual(preferences.commandPaletteShortcut, .controlOptionReturn)
    }

    func testARecordedShortcutRoundTrips() throws {
        let recorded = HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey))
        let data = try JSONEncoder().encode(recorded)
        XCTAssertEqual(try JSONDecoder().decode(HotKey.self, from: data), recorded)
    }

    func testRecordingNeedsARealModifier() {
        XCTAssertEqual(
            try HotKey.recorded(keyCode: UInt16(kVK_ANSI_K), flags: [.control, .option]).get(),
            HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey))
        )
        XCTAssertEqual(HotKey.recorded(keyCode: UInt16(kVK_ANSI_K), flags: []).failure, .needsModifier)
        // Shift alone changes what a key types; it is not enough.
        XCTAssertEqual(HotKey.recorded(keyCode: UInt16(kVK_ANSI_K), flags: [.shift]).failure, .needsModifier)
        // Function keys can stand alone.
        XCTAssertNotNil(try? HotKey.recorded(keyCode: UInt16(kVK_F5), flags: []).get())
    }

    func testShortcutsEveryAppReliesOnAreRefused() {
        XCTAssertEqual(HotKey.recorded(keyCode: UInt16(kVK_ANSI_Q), flags: [.command]).failure, .reserved)
        XCTAssertEqual(HotKey.recorded(keyCode: UInt16(kVK_ANSI_C), flags: [.command]).failure, .reserved)
        XCTAssertNotNil(try? HotKey.recorded(keyCode: UInt16(kVK_ANSI_Q), flags: [.command, .option]).get())
    }

    func testLabelsReadTheWayMacOSWritesShortcuts() {
        XCTAssertEqual(HotKey.controlOptionSpace.displayName, "⌃⌥ Space")
        XCTAssertEqual(HotKey.commandShiftSpace.displayName, "⇧⌘ Space")
        XCTAssertEqual(HotKey.controlOptionReturn.displayName, "⌃⌥ Return")
        XCTAssertEqual(HotKey(keyCode: UInt32(kVK_F6), modifiers: 0).displayName, "F6")
        // A letter is named by the current keyboard layout.
        XCTAssertEqual(HotKey.controlOptionC.keyName.count, 1)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
