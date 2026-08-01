import AppKit
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
        case custom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .graphite: return "Graphite"
            case .ocean: return "Ocean"
            case .sunset: return "Sunset"
            case .forest: return "Forest"
            case .violet: return "Violet"
            case .custom: return "Custom"
            }
        }

        var color: Color {
            switch self {
            case .graphite: return Color(red: 0.78, green: 0.80, blue: 0.83)
            case .ocean: return Color(red: 0.29, green: 0.62, blue: 0.98)
            case .sunset: return Color(red: 0.99, green: 0.45, blue: 0.34)
            case .forest: return Color(red: 0.32, green: 0.80, blue: 0.55)
            case .violet: return Color(red: 0.68, green: 0.47, blue: 0.98)
            case .custom: return .white
            }
        }

        /// Pro tiers unlock the non-default accents.
        var requiresPro: Bool { self != .graphite }
    }

    enum PanelStyle: String, CaseIterable, Codable, Identifiable {
        case black
        case gradient
        case tinted

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .black: return "Pure black"
            case .gradient: return "Soft gradient"
            case .tinted: return "Accent tint"
            }
        }
    }

    // MARK: Surfaces

    static let surface = Color.black
    static let surfaceElevated = Color(white: 0.11)
    static let hairline = Color.white.opacity(0.10)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.38)

    /// Fill for the expanded panel.
    ///
    /// Flat black is right where the panel abuts the hardware notch, but a large
    /// slab of it reads as a hole in the screen rather than as a surface. The
    /// gradient stays black at the very top — so the seam with the notch is still
    /// invisible — and lifts a couple of percent by the bottom edge, which is
    /// just enough to give the panel a body.
    static func panelFill(style: PanelStyle, accent: Color, opacity: Double) -> AnyShapeStyle {
        let opacity = min(max(opacity, 0.65), 1)
        switch style {
        case .black:
            return AnyShapeStyle(Color.black.opacity(opacity))
        case .gradient:
            return AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: .black.opacity(opacity), location: 0),
                    .init(color: .black.opacity(opacity), location: 0.34),
                    .init(color: Color(white: 0.055).opacity(opacity), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
        case .tinted:
            return AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: .black.opacity(opacity), location: 0),
                    .init(color: accent.opacity(0.12 * opacity), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }

    /// Rim light along the panel's edge. Brightest at the bottom corners, where a
    /// real object would catch the light coming off the display.
    static func panelRim(strength: Double) -> AnyShapeStyle {
        let strength = min(max(strength, 0), 1)
        return AnyShapeStyle(LinearGradient(
            stops: [
                .init(color: .white.opacity(0.05 * strength), location: 0),
                .init(color: .white.opacity(0.06 * strength), location: 0.5),
                .init(color: .white.opacity(0.14 * strength), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        ))
    }

    // MARK: Metrics

    /// Concave fillet where the panel meets the top edge of the screen.
    static let flareRadius: CGFloat = 11
    /// Convex radius on the two bottom corners.
    static let bottomRadius: CGFloat = 24
    static let peekBottomRadius: CGFloat = 15
    static let collapsedBottomRadius: CGFloat = 10

    static let contentPadding: CGFloat = 16
    /// Card padding on the Home tab, which stacks two rows where the other tabs
    /// have one.
    static let compactCardPadding: CGFloat = 8
    static let widgetSpacing: CGFloat = 12
}

extension Color {
    init?(hexRGB: String) {
        let value = hexRGB.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    var hexRGB: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}

extension View {
    /// Fades a horizontally-clipped run of text out at both ends, so an
    /// overflowing title dissolves instead of being chopped off mid-glyph.
    func edgeFade(_ width: CGFloat = 12) -> some View {
        mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
            }
        )
    }
}

extension View {
    /// Standard row treatment used inside the expanded panel.
    ///
    /// - Parameter padding: tightened on the Home tab, which has to fit two rows
    ///   of cards into the same panel every other tab fills with one.
    func notchCard(padding: CGFloat = 10) -> some View {
        self.padding(padding)
            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}
