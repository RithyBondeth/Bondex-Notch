import AppKit
import XCTest
@testable import BondexNotch

/// The palette drives the accent every control in the panel is drawn with, so
/// the properties that matter are not "which colour" but "is the answer usable":
/// legible on a near-black surface, stable, and never nil for artwork that
/// plainly has a colour in it.
final class ArtworkPaletteTests: XCTestCase {

    // MARK: Helpers

    private func image(_ draw: (NSSize) -> Void, size: CGFloat = 120) -> NSImage {
        let dimensions = NSSize(width: size, height: size)
        let image = NSImage(size: dimensions)
        image.lockFocus()
        draw(dimensions)
        image.unlockFocus()
        return image
    }

    private func filled(_ color: NSColor) -> NSImage {
        image { size in
            color.setFill()
            NSRect(origin: .zero, size: size).fill()
        }
    }

    // MARK: Extraction

    func testFindsTheDominantHue() throws {
        let palette = try XCTUnwrap(
            ArtworkPalette.extract(from: filled(NSColor(srgbRed: 0.1, green: 0.5, blue: 0.2, alpha: 1)))
        )
        let primary = palette.primary
        XCTAssertGreaterThan(primary.green, primary.red, "green cover should stay green")
        XCTAssertGreaterThan(primary.green, primary.blue, "green cover should stay green")
    }

    func testSecondColourIsAHueApartFromTheFirst() throws {
        // Half orange, half blue: the wash is two colours or it is pointless.
        let art = image { size in
            NSColor(srgbRed: 0.95, green: 0.45, blue: 0.1, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: size.width / 2, height: size.height).fill()
            NSColor(srgbRed: 0.15, green: 0.35, blue: 0.9, alpha: 1).setFill()
            NSRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height).fill()
        }

        let palette = try XCTUnwrap(ArtworkPalette.extract(from: art))
        XCTAssertNotEqual(
            palette.primary, palette.secondary,
            "two flat, opposite hues must not collapse to one colour"
        )
    }

    /// The one failure mode that reaches the user as "the app looks broken":
    /// a dark cover producing an accent that cannot be seen on a black panel.
    func testDarkArtworkStillYieldsALegibleAccent() throws {
        let art = filled(NSColor(srgbRed: 0.10, green: 0.02, blue: 0.03, alpha: 1))
        let palette = try XCTUnwrap(ArtworkPalette.extract(from: art))
        XCTAssertGreaterThan(
            palette.primary.luminance, 0.35,
            "a near-black cover must still be lifted into a visible accent"
        )
    }

    func testGreyscaleArtworkYieldsAGreyAccentRatherThanNothing() throws {
        let palette = try XCTUnwrap(ArtworkPalette.extract(from: filled(NSColor(white: 0.55, alpha: 1))))
        XCTAssertGreaterThan(palette.primary.luminance, 0.3)
    }

    /// Fully transparent art is what a logo dragged out of a browser looks like,
    /// and its premultiplied pixels are all black — reading them as colour would
    /// tint the whole panel from an image with nothing in it.
    func testFullyTransparentArtworkHasNoPalette() {
        let art = image { size in
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: size).fill()
        }
        XCTAssertNil(ArtworkPalette.extract(from: art))
    }

    // MARK: Cache

    @MainActor
    func testPaletteIsRecomputedOnlyWhenTheTrackChanges() {
        let cache = ArtworkPaletteCache()
        let red = filled(NSColor(srgbRed: 0.9, green: 0.15, blue: 0.15, alpha: 1))
        let blue = filled(NSColor(srgbRed: 0.15, green: 0.2, blue: 0.9, alpha: 1))

        let first = cache.palette(for: red, key: "track-a")
        XCTAssertNotNil(first)

        // Same key, different image: the poll republishes the track once a second
        // and must not pay for extraction each time.
        XCTAssertEqual(cache.palette(for: blue, key: "track-a"), first)

        let second = cache.palette(for: blue, key: "track-b")
        XCTAssertNotEqual(second, first)

        XCTAssertNil(cache.palette(for: nil, key: "track-b"), "no artwork means no palette")
    }
}
