import SwiftUI

/// The panel silhouette: flush with the top of the display, concave fillets
/// where it meets the menu bar, convex corners along the bottom.
///
/// The fillets are drawn *outside* the body, so the visible body spans
/// `rect.width - 2 * flareRadius`. Content is inset to match.
struct NotchShape: Shape {

    var flareRadius: CGFloat
    var bottomRadius: CGFloat

    /// Lets both radii interpolate while the panel springs open.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flareRadius, bottomRadius) }
        set {
            flareRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // Clamp so a short panel cannot produce self-intersecting arcs.
        let flare = min(flareRadius, rect.width / 2)
        let bottom = min(bottomRadius, max(rect.height - 1, 0), max(rect.width / 2 - flare, 0))

        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left concave fillet, curving down and inward.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + flare, y: rect.minY + flare),
            control: CGPoint(x: rect.minX + flare, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX + flare, y: rect.maxY - bottom))

        // Bottom-left convex corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + flare + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + flare, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - flare - bottom, y: rect.maxY))

        // Bottom-right convex corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - flare, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - flare, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - flare, y: rect.minY + flare))

        // Top-right concave fillet.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - flare, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
