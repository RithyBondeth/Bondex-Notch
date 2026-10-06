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
    static var surfaceElevated: Color {
        Color(white: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.16 : 0.085)
    }
    static var surfaceRaised: Color {
        Color(white: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.22 : 0.135)
    }
    static var hairline: Color {
        Color.white.opacity(
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.32 : 0.16
        )
    }
    static let primaryText = Color.white
    /// An agent waiting on you. Amber: urgent enough to catch the eye beside
    /// the menu bar, without the alarm of red, and distinct from every agent's
    /// own tint.
    static let attention = Color(red: 1.0, green: 0.72, blue: 0.22)
    static var secondaryText: Color {
        Color.white.opacity(
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.86 : 0.68
        )
    }
    /// Small captions use this color, so it stays above normal-text contrast
    /// instead of acting like decorative chrome.
    static var tertiaryText: Color {
        Color.white.opacity(
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.78 : 0.56
        )
    }

    /// Fill for the expanded panel.
    ///
    /// Flat black is right where the panel abuts the hardware notch, but a large
    /// slab of it reads as a hole in the screen rather than as a surface. The
    /// gradient stays black at the very top — so the seam with the notch is still
    /// invisible — and lifts a couple of percent by the bottom edge, which is
    /// just enough to give the panel a body.
    static func panelFill(style: PanelStyle, accent: Color, opacity: Double) -> AnyShapeStyle {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            return AnyShapeStyle(Color.black)
        }
        let opacity = min(max(opacity, 0.65), 1)
        switch style {
        case .black:
            return AnyShapeStyle(Color.black.opacity(opacity))
        case .gradient:
            return AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: .black.opacity(opacity), location: 0),
                    .init(color: Color(red: 0.018, green: 0.021, blue: 0.029).opacity(opacity), location: 0.42),
                    .init(color: Color(red: 0.035, green: 0.039, blue: 0.05).opacity(opacity), location: 1)
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

    /// A restrained pool of colour below the hardware notch. It gives the
    /// expanded surface a focal point without turning the entire panel into an
    /// accent-coloured slab.
    static func panelGlow(accent: Color) -> AnyShapeStyle {
        AnyShapeStyle(RadialGradient(
            colors: [accent.opacity(0.14), accent.opacity(0.035), .clear],
            center: UnitPoint(x: 0.5, y: 0.02),
            startRadius: 0,
            endRadius: 260
        ))
    }

    // MARK: Metrics

    /// Concave fillet where the panel meets the top edge of the screen.
    static let flareRadius: CGFloat = 11
    /// Convex radius on the two bottom corners.
    static let bottomRadius: CGFloat = 20
    static let peekBottomRadius: CGFloat = 15
    static let collapsedBottomRadius: CGFloat = 10

    static let contentPadding: CGFloat = 14
    /// Card padding on the Home tab, which stacks two rows where the other tabs
    /// have one.
    static let compactCardPadding: CGFloat = 8
    static let widgetSpacing: CGFloat = 8

    /// The panel's type scale.
    ///
    /// Every label uses one of these five steps. Sizes had drifted to a dozen
    /// values half a point apart from widget to widget — 9 here, 9.5 there,
    /// 10 beside 10.5 — which reads as slightly-off rather than as hierarchy.
    /// Symbol sizes are not part of this: they are tuned to the frames they sit
    /// in. Hero figures (the spend total, gauge readouts) stay bespoke.
    enum TextSize {
        /// Badges, tags, the smallest annotations.
        static let micro: CGFloat = 8.5
        /// Secondary lines: subtitles, counts, timestamps, list headers.
        static let caption: CGFloat = 9.5
        /// Row titles and inline controls.
        static let footnote: CGFloat = 10.5
        /// Card titles and primary values.
        static let body: CGFloat = 11.5
        /// The largest text in the panel: player titles, the palette field.
        static let title: CGFloat = 13
    }

    /// Corner radii, from the outermost surface inwards.
    enum Radius {
        /// Cards: a widget's own surface.
        static let card: CGFloat = 13
        /// Rows inside a list, and tiles.
        static let row: CGFloat = 10
        /// Small controls and thumbnails inside a row.
        static let control: CGFloat = 7
    }
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
            .background(
                LinearGradient(
                    colors: [Theme.surfaceRaised.opacity(0.72), Theme.surfaceElevated],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.20), Theme.hairline.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }
}

extension View {
    /// A row inside a list tab: flatter than a card, so a column of them reads
    /// as one list rather than a stack of separate surfaces.
    ///
    /// Clipboard, Capture, Activity, Live and Files each drew their own version,
    /// with paddings of 5–7pt, radii of 9–13pt and a card's shadow on some.
    func notchRow() -> some View {
        self.padding(.vertical, 6)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.surfaceElevated)
            )
    }
}

/// The count-and-actions line above a list.
struct NotchListHeader<Actions: View>: View {
    let title: String
    @ViewBuilder var actions: () -> Actions

    init(_ title: String, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.actions = actions
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: Theme.TextSize.caption, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
            Spacer(minLength: 6)
            actions()
        }
    }
}

extension NotchListHeader where Actions == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// A text-only action in a list header: "Clear", "Search".
struct NotchTextButton: View {
    let title: String
    var tint: Color = Theme.secondaryText
    let action: () -> Void

    @State private var isHovering = false

    init(_ title: String, tint: Color = Theme.secondaryText, action: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: Theme.TextSize.caption, weight: .medium))
            .foregroundStyle(isHovering ? Theme.primaryText : tint)
            .onHover { isHovering = $0 }
            .animation(Motion.hover, value: isHovering)
    }
}

extension View {
    /// Draws a text field's placeholder in the panel's own text colour.
    ///
    /// Apply to a `TextField` created with an empty title. The system
    /// placeholder colour is tuned for an ordinary window: in Light mode it is
    /// near-black, and even in Dark mode it is a faint grey that all but
    /// disappears on the panel's near-black fields. Drawn behind the field, so
    /// focus, submit and typing all still belong to the field itself.
    func notchPlaceholder(_ placeholder: String, isShown: Bool, font: Font) -> some View {
        background(alignment: .leading) {
            if isShown {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
