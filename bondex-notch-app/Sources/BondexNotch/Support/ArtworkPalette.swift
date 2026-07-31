import AppKit
import SwiftUI

/// The two or three colours that make a piece of album art recognisable, pulled
/// out so the panel can light itself from whatever is playing.
///
/// Stored as raw components rather than `Color` so the type is `Sendable` and
/// cheaply `Equatable` — the panel diffs against the current palette on every
/// poll, and comparing `Color` values means comparing opaque boxes.
struct ArtworkPalette: Equatable, Sendable {

    struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        var color: Color { Color(red: red, green: green, blue: blue) }

        /// Perceived brightness, weighted the way the eye actually responds.
        /// A flat average calls saturated blue as bright as yellow, which is what
        /// makes naive "is this dark?" checks pick unreadable text colours.
        var luminance: Double { red * 0.2126 + green * 0.7152 + blue * 0.0722 }

        /// Brightest and dimmest channel. Used to decide whether a pixel is black
        /// or blown out, which luminance answers badly: its weights make a
        /// saturated blue score lower than a dark grey, so a luminance floor
        /// throws away the colour of exactly the dark covers that need it most.
        var value: Double { max(red, green, blue) }
        var floor: Double { min(red, green, blue) }

        var saturation: Double {
            guard value > 0 else { return 0 }
            return (value - floor) / value
        }

        /// Same hue, forced into a brightness band that reads on a near-black
        /// panel. Artwork is full of colours that are perfectly good *as art* and
        /// illegible as an accent — a black-metal cover is not a usable tint.
        func legible(minimumLuminance: Double = 0.42) -> RGB {
            var rgb = self
            // Wash out first: a nearly-grey colour brightened alone just goes
            // white, losing the only thing that made it worth extracting.
            if rgb.saturation < 0.35 {
                rgb = rgb.saturated(to: 0.35)
            }
            let luminance = rgb.luminance
            guard luminance > 0.001 else {
                return RGB(red: 0.72, green: 0.74, blue: 0.78)
            }
            guard luminance < minimumLuminance else { return rgb }
            let scale = minimumLuminance / luminance
            return RGB(
                red: min(rgb.red * scale, 1),
                green: min(rgb.green * scale, 1),
                blue: min(rgb.blue * scale, 1)
            )
        }

        /// Pushes each channel away from the mean until the colour reaches the
        /// requested saturation.
        private func saturated(to target: Double) -> RGB {
            let mean = (red + green + blue) / 3
            guard mean > 0 else { return self }
            let current = saturation
            guard current < target, current >= 0 else { return self }
            // How far past the current spread the channels have to be pushed.
            let boost = (target + 0.001) / (current + 0.001)
            return RGB(
                red: min(max(mean + (red - mean) * boost, 0), 1),
                green: min(max(mean + (green - mean) * boost, 0), 1),
                blue: min(max(mean + (blue - mean) * boost, 0), 1)
            )
        }
    }

    /// The colour the artwork most reads as, already made legible on black.
    let primary: RGB
    /// A second, hue-distinct colour, used for the far corner of the glow so the
    /// wash has some depth instead of being one flat colour at two opacities.
    let secondary: RGB

    var accent: Color { primary.color }

    // MARK: Extraction

    /// Sample grid used for extraction.
    ///
    /// Deliberately tiny. Everything below is exact enough at 32×32 — the point
    /// is which colours dominate, not where they are — and downsampling to this
    /// size costs well under a millisecond even for a 3000px cover. That matters:
    /// this runs on the main actor (see `ArtworkPaletteCache`), so the budget is
    /// "invisible", not "fast".
    private static let sampleEdge = 32

    /// Pulls a palette out of album art, or returns nil for artwork with nothing
    /// usable in it (a plain grey placeholder, a fully transparent image).
    static func extract(from image: NSImage) -> ArtworkPalette? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return extract(from: cgImage)
    }

    static func extract(from cgImage: CGImage) -> ArtworkPalette? {
        guard let pixels = downsample(cgImage) else { return nil }

        // Colours are bucketed by coarse hue rather than by exact value: a
        // gradient cover has thousands of distinct pixels and no two identical
        // ones, so counting exact colours finds nothing. 12 hue buckets is enough
        // to keep red from merging into orange, and coarse enough that a single
        // shaded object still lands in one bucket.
        var buckets = [Bucket](repeating: Bucket(), count: 12)
        var greyWeight = 0.0
        var greySum = RGB(red: 0, green: 0, blue: 0)

        for pixel in pixels {
            let saturation = pixel.saturation

            // Near-black and blown-out pixels carry no hue worth extracting, and
            // letterboxed art is mostly one or the other. The floor is low on
            // purpose: plenty of covers are almost entirely dark, and the panel
            // still has to find their colour rather than give up and go grey.
            guard pixel.value > 0.08, pixel.floor < 0.96 else { continue }

            guard saturation > 0.18 else {
                greyWeight += 1
                greySum.red += pixel.red
                greySum.green += pixel.green
                greySum.blue += pixel.blue
                continue
            }

            // Weight by how colourful the pixel is, so a small saturated logo
            // beats a large muddy background — which is what the eye does too.
            let weight = saturation * saturation
            buckets[hueBucket(of: pixel)].add(pixel, weight: weight)
        }

        let ranked = buckets.filter { $0.weight > 0 }.sorted { $0.weight > $1.weight }

        guard let first = ranked.first else {
            // No hue anywhere: a black-and-white cover. Use its own grey so the
            // glow still tracks how light or dark the art is.
            guard greyWeight > 0 else { return nil }
            let grey = RGB(
                red: greySum.red / greyWeight,
                green: greySum.green / greyWeight,
                blue: greySum.blue / greyWeight
            ).legible()
            return ArtworkPalette(primary: grey, secondary: grey)
        }

        let primary = first.average.legible()
        // Skip the neighbouring bucket for the second colour: adjacent hues are
        // usually the same object's shading, and two near-identical colours make
        // the glow look like a rendering mistake rather than a choice.
        let secondary = ranked
            .dropFirst()
            .first { isDistinct($0, from: first) }?
            .average
            .legible(minimumLuminance: 0.34)

        return ArtworkPalette(primary: primary, secondary: secondary ?? primary)
    }

    // MARK: Bucketing

    private struct Bucket {
        var weight = 0.0
        private var red = 0.0, green = 0.0, blue = 0.0

        mutating func add(_ pixel: RGB, weight pixelWeight: Double) {
            weight += pixelWeight
            red += pixel.red * pixelWeight
            green += pixel.green * pixelWeight
            blue += pixel.blue * pixelWeight
        }

        var average: RGB {
            guard weight > 0 else { return RGB(red: 0, green: 0, blue: 0) }
            return RGB(red: red / weight, green: green / weight, blue: blue / weight)
        }
    }

    private static func hueBucket(of pixel: RGB) -> Int {
        let hue = NSColor(
            srgbRed: pixel.red, green: pixel.green, blue: pixel.blue, alpha: 1
        ).hueComponent
        return min(Int(hue * 12), 11)
    }

    /// Two buckets count as different colours when they are more than one bucket
    /// apart on the hue wheel, measured the short way round so red and magenta
    /// are correctly seen as neighbours.
    private static func isDistinct(_ candidate: Bucket, from primary: Bucket) -> Bool {
        let a = hueBucket(of: candidate.average)
        let b = hueBucket(of: primary.average)
        let distance = abs(a - b)
        return min(distance, 12 - distance) > 1
    }

    // MARK: Pixels

    /// Redraws the image into a small RGBA buffer and returns its pixels.
    ///
    /// Going through Core Graphics rather than reading the original bitmap does
    /// the colour-space conversion, the premultiplication and the scaling in one
    /// step, and gives a known layout on the other side — album art arrives as
    /// anything from an indexed PNG to a CMYK JPEG, and handling those by hand is
    /// how palette extraction ends up with swapped channels on some covers.
    private static func downsample(_ image: CGImage) -> [RGB]? {
        let edge = sampleEdge
        var buffer = [UInt8](repeating: 0, count: edge * edge * 4)

        let drawn: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: edge,
                    height: edge,
                    bitsPerComponent: 8,
                    bytesPerRow: edge * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }

            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))
            return true
        }
        guard drawn else { return nil }

        var pixels: [RGB] = []
        pixels.reserveCapacity(edge * edge)
        for index in stride(from: 0, to: buffer.count, by: 4) {
            let alpha = Double(buffer[index + 3]) / 255
            // Transparent art is common for logos dragged out of a browser, and
            // its premultiplied pixels are all black.
            guard alpha > 0.5 else { continue }
            pixels.append(RGB(
                red: Double(buffer[index]) / 255 / alpha,
                green: Double(buffer[index + 1]) / 255 / alpha,
                blue: Double(buffer[index + 2]) / 255 / alpha
            ))
        }
        return pixels.isEmpty ? nil : pixels
    }
}

// MARK: - Cache

/// Remembers the palette for the artwork currently on screen.
///
/// Extraction is cheap but not free, and `nowPlaying` republishes once a second
/// with the same image attached — so the guard that matters is not making it
/// fast, it is not running it sixty times per track.
@MainActor
final class ArtworkPaletteCache {

    private var key: String?
    private var cached: ArtworkPalette?

    /// - Parameter key: identity of the *track*, so the palette is recomputed
    ///   when the art changes rather than when the object identity does.
    func palette(for image: NSImage?, key trackKey: String?) -> ArtworkPalette? {
        guard let image, let trackKey else {
            key = nil
            cached = nil
            return nil
        }
        guard trackKey != key else { return cached }
        key = trackKey
        cached = ArtworkPalette.extract(from: image)
        return cached
    }
}
