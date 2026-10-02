import SwiftUI

/// An SF Symbol, or one of Bondex's own glyphs where SF Symbols has none.
///
/// Icons travel through the app as names — a tab's, a command's, a custom
/// action's — so a custom glyph is a name too, under a `bondex.` prefix that SF
/// Symbols can never use. Anything that renders one of those names goes through
/// here; `Image(systemName:)` on its own would draw nothing.
struct SymbolIcon: View {
    let name: String
    /// The point size the SF Symbol would be drawn at, so a custom glyph sits
    /// at the same optical size beside it.
    var size: CGFloat = 13
    var weight: Font.Weight = .regular

    var body: some View {
        switch name {
        case RobotGlyph.symbolName:
            RobotGlyph()
                .fill(style: FillStyle(eoFill: true))
                .frame(width: size * 1.18, height: size * 1.18)
        default:
            Image(systemName: name)
                .font(.system(size: size, weight: weight))
        }
    }
}

extension Label where Title == Text, Icon == SymbolIcon {
    /// A `Label` whose icon may be one of Bondex's own glyphs.
    init(_ title: String, symbol: String) {
        self.init { Text(title) } icon: { SymbolIcon(name: symbol) }
    }
}

/// A robot head: antenna, ears, two eyes and a mouth, the eyes and mouth cut
/// out of the head with the even-odd rule. SF Symbols has no robot, and the
/// Agents tab wants one.
///
/// Drawn on a 16-unit grid like the agent marks, and kept to shapes that stay
/// legible at the 9-point size of a tab chip: nothing thinner than a unit.
struct RobotGlyph: Shape {
    static let symbolName = "bondex.robot"

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 16
        let origin = CGPoint(
            x: rect.midX - unit * 8,
            y: rect.midY - unit * 8
        )
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: origin.x + x * unit, y: origin.y + y * unit, width: w * unit, height: h * unit)
        }

        var path = Path()
        // Antenna: a ball on a stem.
        path.addEllipse(in: box(6.5, 0.2, 3, 3))
        path.addRoundedRect(in: box(7.3, 2.6, 1.4, 2.4), cornerSize: CGSize(width: unit * 0.4, height: unit * 0.4))
        // Ears.
        path.addRoundedRect(in: box(0.2, 7.2, 2, 4), cornerSize: CGSize(width: unit * 0.8, height: unit * 0.8))
        path.addRoundedRect(in: box(13.8, 7.2, 2, 4), cornerSize: CGSize(width: unit * 0.8, height: unit * 0.8))
        // Head.
        path.addRoundedRect(in: box(2.6, 4.6, 10.8, 10), cornerSize: CGSize(width: unit * 3, height: unit * 3))
        // Eyes and mouth, wound inside the head so even-odd cuts them out.
        path.addEllipse(in: box(4.7, 7.4, 2.6, 2.6))
        path.addEllipse(in: box(8.7, 7.4, 2.6, 2.6))
        path.addRoundedRect(in: box(5.6, 11.4, 4.8, 1.3), cornerSize: CGSize(width: unit * 0.65, height: unit * 0.65))
        return path
    }
}
