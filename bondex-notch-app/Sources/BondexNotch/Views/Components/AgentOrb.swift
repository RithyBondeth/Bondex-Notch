import AppKit
import SwiftUI

/// The "an agent is working" mark: the agent's glyph breathing inside a ring
/// that sweeps around it.
///
/// This is on screen for as long as the agent is working — which for a long
/// refactor is measured in tens of minutes — so it is built the same way
/// `AudioBars` is, and for the same measured reason. Expressed as a SwiftUI
/// `repeatForever` or a `TimelineView`, a continuous animation stays on the
/// display cycle and re-renders the whole panel every frame, at a cost of
/// 5–10% CPU for as long as it runs. Handed to Core Animation as two
/// `CABasicAnimation`s on detached layers, the render server interpolates it and
/// the app does no per-frame work at all.
///
/// The two motions are deliberately at odds: the sweep is linear and constant,
/// the breath is eased and slower, and their periods share no common multiple.
/// Locked together they would read as one mechanical throb; drifting apart they
/// read as something alive and thinking.
struct AgentOrb: View {
    var kind: AgentKind
    var size: CGFloat = 21
    /// Ring off, glyph still: used where the mark is a label rather than a
    /// report of live work.
    var isAnimating = true

    @Environment(\.isRenderingOffscreen) private var isRenderingOffscreen

    var body: some View {
        if isRenderingOffscreen {
            // `ImageRenderer` cannot rasterise an `NSViewRepresentable`, so the
            // preview tool gets a still of the same composition.
            ZStack {
                Circle().stroke(kind.tint.opacity(0.28), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(kind.tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                PixelMark(kind: kind)
                    .frame(width: size * 0.62)
            }
            .frame(width: size, height: size)
        } else {
            AgentOrbLayers(
                kind: kind,
                size: size,
                isAnimating: isAnimating
                    && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
                .frame(width: size, height: size)
        }
    }
}

/// The agent's mark as a plain SwiftUI shape.
///
/// The same geometry the layer draws, for the two places that cannot use a
/// `CAShapeLayer`: the offscreen preview renderer, and Settings.
struct PixelMark: View {
    let kind: AgentKind

    var body: some View {
        AgentMarkShape(kind: kind)
            .fill(kind.tint, style: FillStyle(eoFill: true))
            // Sized from the mark itself, so a caller only has to set the width.
            .aspectRatio(AgentMarks.aspect(for: kind), contentMode: .fit)
    }
}

private struct AgentMarkShape: Shape {
    let kind: AgentKind

    func path(in rect: CGRect) -> Path {
        Path(AgentMarks.path(for: kind, in: CGRect(origin: .zero, size: rect.size)))
            // `Shape` draws in a flipped space, so a mark built for layer
            // geometry — origin at the bottom — has to be turned back over here.
            .applying(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -rect.height))
    }
}

private struct AgentOrbLayers: NSViewRepresentable {
    var kind: AgentKind
    var size: CGFloat
    var isAnimating: Bool

    func makeNSView(context: Context) -> AgentOrbView {
        AgentOrbView(kind: kind, size: size)
    }

    func updateNSView(_ view: AgentOrbView, context: Context) {
        view.update(kind: kind, isAnimating: isAnimating)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: AgentOrbView,
        context: Context
    ) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

final class AgentOrbView: NSView {

    private let track = CAShapeLayer()
    private let sweep = CAShapeLayer()
    private let glyph = CAShapeLayer()

    private var kind: AgentKind
    private let size: CGFloat
    private var isAnimating = false

    init(kind: AgentKind, size: CGFloat) {
        self.kind = kind
        self.size = size
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.masksToBounds = false

        for shape in [track, sweep] {
            shape.fillColor = nil
            shape.lineWidth = max(size * 0.075, 1.2)
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }
        glyph.contentsGravity = .resizeAspect
        layer?.addSublayer(glyph)

        applyTint()
        applyGlyph()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: size, height: size) }

    /// Rotation animates the layer, so the layer's own geometry must not also be
    /// changing — hence anchor points at the centre and positions set once here.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let box = bounds
        let inset = sweep.lineWidth / 2
        let circle = CGPath(
            ellipseIn: box.insetBy(dx: inset, dy: inset),
            transform: nil
        )
        track.path = circle
        sweep.path = circle

        for shape in [track, sweep] {
            shape.frame = box
            shape.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            shape.position = CGPoint(x: box.midX, y: box.midY)
        }

        // Claude's grid is 16 cells wide and 10 tall; the drawn marks are square.
        // A square box for either would stretch one of them.
        let aspect = AgentMarks.aspect(for: kind)
        let glyphWidth = box.width * (aspect > 1 ? 0.62 : 0.52)
        let glyphHeight = glyphWidth / aspect
        glyph.bounds = CGRect(x: 0, y: 0, width: glyphWidth, height: glyphHeight)
        glyph.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        glyph.position = CGPoint(x: box.midX, y: box.midY)
        applyGlyph()

        CATransaction.commit()
    }

    func update(kind newKind: AgentKind, isAnimating animating: Bool) {
        if newKind != kind {
            kind = newKind
            applyTint()
            applyGlyph()
        }
        guard animating != isAnimating else { return }
        isAnimating = animating
        animating ? start() : stop()
    }

    private func applyTint() {
        let tint = NSColor(kind.tint)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.strokeColor = tint.withAlphaComponent(0.22).cgColor
        sweep.strokeColor = tint.cgColor
        // Only part of the circle is stroked; rotating that is the sweep.
        sweep.strokeStart = 0
        sweep.strokeEnd = 0.28
        CATransaction.commit()
    }

    /// Every mark is a path now, including the ones that are drawn as lines —
    /// `AgentMarks` strokes those into outlines — so there is one way to draw a
    /// glyph and one place to set its colour. The bitmap-and-`sourceAtop` dance
    /// that tinting an SF Symbol needed is gone with it.
    private func applyGlyph() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        glyph.contents = nil
        glyph.fillRule = AgentMarks.fillRule == .evenOdd ? .evenOdd : .nonZero
        glyph.fillColor = NSColor(kind.tint).cgColor
        glyph.path = AgentMarks.path(for: kind, in: glyph.bounds)
    }

    /// One rounded rect per filled cell, unioned into a single path.
    ///
    /// Row 0 is the *top* row, while layer geometry has its origin at the
    /// bottom — so rows are laid out upwards from the far edge, or the mark
    /// comes out upside down.
    static func path(for mark: [String], in box: CGRect) -> CGPath {
        let columns = mark.map(\.count).max() ?? 0
        guard columns > 0, !mark.isEmpty, box.width > 0 else { return CGMutablePath() }

        let cell = CGSize(
            width: box.width / CGFloat(columns),
            height: box.height / CGFloat(mark.count)
        )
        let path = CGMutablePath()
        for (row, line) in mark.enumerated() {
            for (column, character) in line.enumerated() where character == "X" {
                // Exactly one cell, with no overlap to close seams with. Every
                // rect goes into a single path filled in one pass, so the
                // rasteriser unions them and shared edges never show — whereas
                // dilating each cell to be safe closes the *gaps* instead. At
                // 21pt the whole mark is 13pt wide, so a cell is under a point
                // and the eyes are a single cell: a third of a point of slop in
                // each direction is the difference between a face and a blob.
                path.addRect(CGRect(
                    x: CGFloat(column) * cell.width,
                    y: box.height - CGFloat(row + 1) * cell.height,
                    width: cell.width,
                    height: cell.height
                ))
            }
        }
        return path
    }

    private func start() {
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -Double.pi * 2      // Clockwise on screen.
        spin.duration = 1.9
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        sweep.add(spin, forKey: "spin")

        // Slower than the sweep and eased, so the two never settle into step.
        let breath = CABasicAnimation(keyPath: "transform.scale")
        breath.fromValue = 0.82
        breath.toValue = 1.0
        breath.duration = 1.15
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glyph.add(breath, forKey: "breath")
    }

    private func stop() {
        sweep.removeAnimation(forKey: "spin")
        glyph.removeAnimation(forKey: "breath")
        // Settle back to rest rather than freezing mid-breath at whatever scale
        // the loop happened to have reached.
        let settle = CABasicAnimation(keyPath: "transform.scale")
        settle.duration = 0.2
        settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
        glyph.add(settle, forKey: "settle")
        glyph.setValue(1.0, forKeyPath: "transform.scale")
    }
}
