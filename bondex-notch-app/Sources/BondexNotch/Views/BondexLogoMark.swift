import AppKit
import SwiftUI

/// The product mark shared by branded app surfaces. Keeping the geometry in
/// SwiftUI lets the small menu-bar version stay sharp and template-tintable.
struct BondexLogoMark: View {
    enum Style {
        case color
        case template
    }

    var style: Style = .color

    var body: some View {
        ZStack {
            TopLogoPiece()
                .fill(topStyle)
            BottomLogoPiece()
                .fill(bottomStyle)
            RightLogoPiece()
                .fill(rightStyle)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @MainActor
    static func menuBarImage() -> NSImage? {
        let renderer = ImageRenderer(
            content: BondexLogoMark(style: .template)
                .frame(width: 18, height: 18)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.isOpaque = false

        guard let image = renderer.nsImage else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Bondex Notch"
        return image
    }

    private var topStyle: AnyShapeStyle {
        switch style {
        case .color:
            AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.235, green: 0.757, blue: 0.965),
                    Color(red: 0.133, green: 0.659, blue: 0.929)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        case .template:
            AnyShapeStyle(Color.black)
        }
    }

    private var bottomStyle: AnyShapeStyle {
        switch style {
        case .color:
            AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.137, green: 0.412, blue: 0.875),
                    Color(red: 0.094, green: 0.298, blue: 0.780)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        case .template:
            AnyShapeStyle(Color.black)
        }
    }

    private var rightStyle: AnyShapeStyle {
        switch style {
        case .color:
            AnyShapeStyle(LinearGradient(
                colors: [.white, Color(red: 0.906, green: 0.929, blue: 0.980)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        case .template:
            AnyShapeStyle(Color.black)
        }
    }
}

private struct TopLogoPiece: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(15, 6, in: rect))
        path.addLine(to: point(40, 6, in: rect))
        path.addCurve(
            to: point(50, 16, in: rect),
            control1: point(40, 12.7, in: rect),
            control2: point(43.3, 16, in: rect)
        )
        path.addLine(to: point(50, 39, in: rect))
        path.addCurve(
            to: point(38, 51, in: rect),
            control1: point(50, 45.6, in: rect),
            control2: point(44.6, 51, in: rect)
        )
        path.addLine(to: point(15, 51, in: rect))
        path.addCurve(
            to: point(3, 39, in: rect),
            control1: point(8.4, 51, in: rect),
            control2: point(3, 45.6, in: rect)
        )
        path.addLine(to: point(3, 18, in: rect))
        path.addCurve(
            to: point(15, 6, in: rect),
            control1: point(3, 11.4, in: rect),
            control2: point(8.4, 6, in: rect)
        )
        path.closeSubpath()
        return path
    }
}

private struct BottomLogoPiece: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(15, 56, in: rect))
        path.addLine(to: point(35.5, 56, in: rect))
        path.addCurve(
            to: point(45.5, 62, in: rect),
            control1: point(39.8, 56, in: rect),
            control2: point(43.5, 58.3, in: rect)
        )
        path.addLine(to: point(60.5, 89.5, in: rect))
        path.addCurve(
            to: point(56, 96, in: rect),
            control1: point(62.3, 92.8, in: rect),
            control2: point(59.8, 96, in: rect)
        )
        path.addLine(to: point(15, 96, in: rect))
        path.addCurve(
            to: point(3, 84, in: rect),
            control1: point(8.4, 96, in: rect),
            control2: point(3, 90.6, in: rect)
        )
        path.addLine(to: point(3, 68, in: rect))
        path.addCurve(
            to: point(15, 56, in: rect),
            control1: point(3, 61.4, in: rect),
            control2: point(8.4, 56, in: rect)
        )
        path.closeSubpath()
        return path
    }
}

private struct RightLogoPiece: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(70, 6, in: rect))
        path.addLine(to: point(83, 6, in: rect))
        path.addCurve(
            to: point(97, 20, in: rect),
            control1: point(90.7, 6, in: rect),
            control2: point(97, 12.3, in: rect)
        )
        path.addLine(to: point(97, 82, in: rect))
        path.addCurve(
            to: point(83, 96, in: rect),
            control1: point(97, 89.7, in: rect),
            control2: point(90.7, 96, in: rect)
        )
        path.addLine(to: point(78.5, 96, in: rect))
        path.addCurve(
            to: point(67.6, 89.3, in: rect),
            control1: point(73.9, 96, in: rect),
            control2: point(69.7, 93.4, in: rect)
        )
        path.addLine(to: point(53.7, 62, in: rect))
        path.addCurve(
            to: point(50, 47.1, in: rect),
            control1: point(51.3, 57.4, in: rect),
            control2: point(50, 52.3, in: rect)
        )
        path.addLine(to: point(50, 22, in: rect))
        path.addCurve(
            to: point(56, 16, in: rect),
            control1: point(50, 18.7, in: rect),
            control2: point(52.7, 16, in: rect)
        )
        path.addLine(to: point(60, 16, in: rect))
        path.addCurve(
            to: point(70, 6, in: rect),
            control1: point(66.7, 16, in: rect),
            control2: point(70, 12.7, in: rect)
        )
        path.closeSubpath()
        return path
    }
}

private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(
        x: rect.minX + (x / 100) * rect.width,
        y: rect.minY + (y / 100) * rect.height
    )
}
