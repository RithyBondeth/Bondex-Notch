import CoreGraphics
import Foundation

/// Every agent's mark, as geometry rather than as an image asset.
///
/// The project ships no image files, and these are the reason it still does not
/// have to. A mark drawn as a path scales to any size without a set of
/// `@2x`/`@3x` exports, and is tinted by *fill* rather than by compositing —
/// which matters because these sit on a near-black panel, where anything with a
/// baked-in background shows as a pale rectangle around the glyph.
///
/// The marks are simplified rather than traced. At the size they are actually
/// used — the orb's glyph is about 13pt across — detail below roughly half a
/// point is not resolvable, so fidelity there costs path complexity and buys
/// nothing. What has to survive simplification is the *silhouette*, because that
/// is what makes a mark recognisable at a glance over the menu bar.
///
/// Used nominatively: each identifies the product it names, which is the one
/// thing a product's mark is always allowed to do.
enum AgentMarks {

    /// Natural width ÷ height for an agent's mark, so callers can size a box for
    /// it without stretching it.
    static func aspect(for kind: AgentKind) -> CGFloat {
        if let mark = kind.pixelMark {
            return 16 / CGFloat(mark.count)
        }
        // Every drawn mark is designed in a square.
        return 1
    }

    /// Marks with interior holes — an eye, a cut-out — are built as one path with
    /// the hole wound as a second subpath, which only reads as a hole under the
    /// even-odd rule. Harmless for the marks without holes: their subpaths never
    /// overlap, so both rules agree.
    static let fillRule: CGPathFillRule = .evenOdd

    /// The mark as a filled path, laid out in `box`.
    ///
    /// Always a *fill*, never a stroke, even for the marks that are drawn as
    /// lines: those are stroked into an outline here (`copy(strokingWithWidth:)`)
    /// so that every caller — the Core Animation layer, the SwiftUI shape, the
    /// offscreen renderer — has one thing to draw and one place to set a colour.
    static func path(for kind: AgentKind, in box: CGRect) -> CGPath {
        // A layer is laid out before it is sized, so this is asked for a zero
        // box on the way past. Every mark answers the same way — nothing to
        // draw — rather than each returning its own degenerate shape: a
        // zero-width stroke in particular is undefined rather than invisible.
        guard box.width > 0, box.height > 0 else { return CGMutablePath() }

        if let mark = kind.pixelMark {
            return AgentOrbView.path(for: mark, in: box)
        }
        switch kind {
        case .codex: return codex(in: box)
        case .gemini: return gemini(in: box)
        case .opencode: return opencode(in: box)
        default: return ollama(in: box)
        }
    }

    // MARK: - Marks
    //
    // Each is written in a unit square with y *down*, the way the artwork reads,
    // and flipped once at the end by `scaled(_:in:)` — layer geometry has its
    // origin at the bottom, and doing the flip per-point is how a mark ends up
    // silently upside down.

    /// Codex: the terminal prompt, `>` over `_`.
    ///
    /// The badge the mark normally sits on is dropped deliberately. It is a
    /// filled, gradient-blue blob, and on this panel a blob would read as a
    /// button rather than as a status. Stripped to the prompt itself, the mark
    /// tints like every other one here.
    private static func codex(in box: CGRect) -> CGPath {
        let stroke = CGMutablePath()
        stroke.move(to: unit(0.24, 0.24, box))
        stroke.addLine(to: unit(0.48, 0.48, box))
        stroke.addLine(to: unit(0.24, 0.72, box))

        stroke.move(to: unit(0.56, 0.72, box))
        stroke.addLine(to: unit(0.82, 0.72, box))

        return stroke.copy(
            strokingWithWidth: box.width * 0.13,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10
        )
    }

    /// Gemini: a four-pointed star with concave sides.
    ///
    /// Each side is one quadratic curve whose control point is the centre, which
    /// is what pulls the waist in to about a third of the radius and gives the
    /// points their taper. Straight lines here would make a plain diamond.
    private static func gemini(in box: CGRect) -> CGPath {
        let path = CGMutablePath()
        let centre = unit(0.5, 0.5, box)
        let tips = [unit(0.5, 0.0, box), unit(1.0, 0.5, box), unit(0.5, 1.0, box), unit(0.0, 0.5, box)]

        path.move(to: tips[0])
        for index in 1...4 {
            path.addQuadCurve(to: tips[index % 4], control: centre)
        }
        path.closeSubpath()
        return path
    }

    /// opencode: a block cursor.
    ///
    /// PROVISIONAL. The supplied artwork did not survive the trip into this
    /// session — it arrived as the empty rectangle a font renders for a glyph it
    /// does not have — so this is a stand-in built from that outline: a filled
    /// block with a rectangular cut-out. It is deliberately plain, and should be
    /// replaced once the real mark is to hand.
    private static func opencode(in box: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(
            in: rect(0.12, 0.06, 0.76, 0.88, box),
            cornerWidth: box.width * 0.06,
            cornerHeight: box.width * 0.06
        )
        // Wound as a second subpath so the even-odd rule punches it out.
        path.addRect(rect(0.32, 0.26, 0.36, 0.48, box))
        return path
    }

    /// Ollama: the llama, as a silhouette.
    ///
    /// Also the mark for any agent Bondex does not know, which is the reason it
    /// is a silhouette rather than the original outline drawing. That drawing is
    /// line art with ears, a muzzle and two eyes inside a 13pt circle; stroked at
    /// that size the lines merge into a smudge. Filled, the ears and the head
    /// still read, and the eyes survive as cut-outs.
    private static func ollama(in box: CGRect) -> CGPath {
        let path = CGMutablePath()

        // Ears: narrow, upright, rounded at the tip.
        for x in [0.24, 0.60] {
            path.addRoundedRect(
                in: rect(x, 0.04, 0.16, 0.34, box),
                cornerWidth: box.width * 0.08,
                cornerHeight: box.width * 0.08
            )
        }

        // Head and body as one rounded mass, widest at the jaw.
        path.addRoundedRect(
            in: rect(0.16, 0.26, 0.68, 0.70, box),
            cornerWidth: box.width * 0.26,
            cornerHeight: box.width * 0.24
        )

        // Eyes, punched out by the even-odd rule.
        for x in [0.30, 0.58] {
            path.addEllipse(in: rect(x, 0.46, 0.12, 0.12, box))
        }
        // Muzzle.
        path.addEllipse(in: rect(0.36, 0.64, 0.28, 0.20, box))

        return path
    }

    // MARK: - Unit helpers

    /// A point in the unit square, with y measured *down* from the top.
    private static func unit(_ x: CGFloat, _ y: CGFloat, _ box: CGRect) -> CGPoint {
        CGPoint(x: box.minX + x * box.width, y: box.minY + (1 - y) * box.height)
    }

    /// A rect in the unit square, with y measured *down* from the top.
    private static func rect(
        _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ box: CGRect
    ) -> CGRect {
        CGRect(
            x: box.minX + x * box.width,
            y: box.minY + (1 - y - height) * box.height,
            width: width * box.width,
            height: height * box.height
        )
    }
}
