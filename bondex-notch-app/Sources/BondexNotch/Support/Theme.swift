import SwiftUI

/// Visual vocabulary for the notch surface.
///
/// The panel physically hangs off the top edge of the display, so everything is
/// tuned for a dark, near-black surface that blends into the hardware notch on
/// Macs that have one.
enum Theme {

    // MARK: Palette

    enum Accent: String, CaseIterable, Codable, Identifiable {
        case graphite
        case ocean
        case sunset
        case forest
        case violet

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .graphite: return "Graphite"
            case .ocean: return "Ocean"
            case .sunset: return "Sunset"
            case .forest: return "Forest"
            case .violet: return "Violet"
            }
        }

        var color: Color {
            switch self {
            case .graphite: return Color(red: 0.78, green: 0.80, blue: 0.83)
            case .ocean: return Color(red: 0.29, green: 0.62, blue: 0.98)
            case .sunset: return Color(red: 0.99, green: 0.45, blue: 0.34)
            case .forest: return Color(red: 0.32, green: 0.80, blue: 0.55)
            case .violet: return Color(red: 0.68, green: 0.47, blue: 0.98)
            }
        }

        /// Pro tiers unlock the non-default accents.
        var requiresPro: Bool { self != .graphite }
    }

    // MARK: Surfaces

    static let surface = Color.black
    static let surfaceElevated = Color(white: 0.10)
    static let hairline = Color.white.opacity(0.10)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.38)

    // MARK: Metrics

    /// Concave fillet where the panel meets the top edge of the screen.
    static let flareRadius: CGFloat = 11
    /// Convex radius on the two bottom corners.
    static let bottomRadius: CGFloat = 22
    static let collapsedBottomRadius: CGFloat = 10

    static let contentPadding: CGFloat = 16
    static let widgetSpacing: CGFloat = 12
}

extension View {
    /// Standard row treatment used inside the expanded panel.
    func notchCard() -> some View {
        padding(10)
            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}
