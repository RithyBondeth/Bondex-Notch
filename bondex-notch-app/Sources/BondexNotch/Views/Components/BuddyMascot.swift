import SwiftUI

/// The wellness buddy: a potted sprout with a face, drawn rather than shipped
/// as artwork so every degree of energy has its own pose.
///
/// Energy bends the stem over, droops the leaves and drains their green
/// towards straw, and the face follows: a grin and a flower when thriving,
/// worried brows and a bead of sweat when tired. It breathes, blinks, and —
/// where it is interactive — watches the pointer and hops when clicked, when
/// it is given water, or when you come back from a break.
struct BuddyMascot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var energy: Double
    var isThirsty = false
    /// Changes each time water is logged; a change plays a splash and a hop.
    var waterTick = 0
    /// Frames per second while idling. Low in the peek, which sits over the
    /// menu bar for as long as a break is due.
    var frameRate: Double = 30
    /// Follows the pointer with its eyes and hops when clicked. Off in the
    /// peek, where a click belongs to the notch.
    var isInteractive = false

    @State private var splashStartedAt: Date?
    @State private var reactionStartedAt: Date?
    /// Where the pointer is, from -1 to 1 across the view each way.
    @State private var gaze: CGPoint = .zero

    /// The part of the 100 × 100 drawing space the buddy occupies.
    private static let viewBox = CGRect(x: 7, y: 12, width: 86, height: 86)
    private static let splashLength: TimeInterval = 0.9
    private static let reactionLength: TimeInterval = 1.1

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1 / frameRate, paused: reduceMotion)) { timeline in
                Canvas { context, size in
                    let side = min(size.width, size.height)
                    context.translateBy(
                        x: (size.width - side) / 2,
                        y: (size.height - side) / 2
                    )
                    context.scaleBy(x: side / Self.viewBox.width, y: side / Self.viewBox.height)
                    context.translateBy(x: -Self.viewBox.minX, y: -Self.viewBox.minY)
                    BuddyDrawing(
                        energy: min(max(energy, 0), 1),
                        isThirsty: isThirsty,
                        time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate,
                        splash: progress(since: splashStartedAt, over: Self.splashLength, at: timeline.date),
                        reaction: progress(since: reactionStartedAt, over: Self.reactionLength, at: timeline.date),
                        gaze: gaze
                    ).draw(in: &context)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard isInteractive else { return }
                switch phase {
                case .active(let location):
                    let size = proxy.size
                    guard size.width > 0, size.height > 0 else { return }
                    gaze = CGPoint(
                        x: min(max(location.x / size.width * 2 - 1, -1), 1),
                        y: min(max(location.y / size.height * 2 - 1, -1), 1)
                    )
                case .ended:
                    gaze = .zero
                }
            }
            .onTapGesture {
                guard isInteractive else { return }
                react()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: waterTick) { _, _ in
            guard !reduceMotion else { return }
            splashStartedAt = Date()
            reactionStartedAt = Date().addingTimeInterval(Self.splashLength * 0.55)
        }
        // A jump in energy is a break just taken: worth a little celebration.
        .onChange(of: energy) { old, new in
            if new - old > 0.15 { react() }
        }
        .help(isInteractive ? "Say hi" : "")
        .accessibilityElement()
        .accessibilityLabel("Wellness buddy")
        .accessibilityValue("\(BuddyMood(energy: energy).title), \(Int((energy * 100).rounded())) percent energy")
        .accessibilityAction(named: "Say hi") { react() }
    }

    private func react() {
        guard !reduceMotion else { return }
        reactionStartedAt = Date()
    }

    private func progress(since start: Date?, over length: TimeInterval, at date: Date) -> Double? {
        guard let start else { return nil }
        let progress = date.timeIntervalSince(start) / length
        return (0..<1).contains(progress) ? progress : nil
    }
}

/// The drawing itself, in a 100 × 100 space: the pot's foot sits at y = 95.
private struct BuddyDrawing {
    let energy: Double
    let isThirsty: Bool
    let time: TimeInterval
    let splash: Double?
    let reaction: Double?
    let gaze: CGPoint

    private var tiredness: Double { 1 - energy }
    private var mood: BuddyMood { BuddyMood(energy: energy) }
    private var isDelighted: Bool { reaction != nil }

    func draw(in context: inout GraphicsContext) {
        drawGlow(&context)
        if mood == .thriving || isDelighted { drawSparkles(&context) }
        drawShadow(&context)

        // Everything that hops and breathes together.
        var buddy = context
        applyBounce(&buddy)
        let stem = stemGeometry()
        drawStem(&buddy, stem)
        drawLeaves(&buddy, stem)
        drawCrown(&buddy, stem)
        drawPot(&buddy)
        drawFace(&buddy)
        if !isDelighted, mood == .droopy || mood == .wilting { drawSweat(&buddy) }

        if mood == .wilting, time > 0 { drawFallingLeaf(&context, from: stem.tip) }
        if isThirsty { drawThirstDrop(&context) }
        if let splash { drawSplash(&context, progress: splash) }
        if let reaction { drawHearts(&context, progress: reaction) }
    }

    // MARK: Motion

    /// How high the buddy is off the ground, mid-hop.
    private var hop: Double {
        guard let reaction else { return 0 }
        return sin(min(reaction / 0.45, 1) * .pi) * 6
    }

    /// Breathing, slower and shallower as energy runs out, plus the squash
    /// and stretch of a hop — all about the foot of the pot.
    private func applyBounce(_ context: inout GraphicsContext) {
        let breath = sin(time * (1.4 + energy)) * 0.014 * (0.4 + energy)
        var stretch = breath
        if let reaction {
            stretch += sin(reaction * .pi * 4) * 0.08 * (1 - reaction)
        }
        context.translateBy(x: 50, y: 95 - hop)
        context.scaleBy(x: 1 - stretch * 0.7, y: 1 + stretch)
        context.translateBy(x: -50, y: -95)
    }

    // MARK: Atmosphere

    private func drawGlow(_ context: inout GraphicsContext) {
        let tint = moodTint
        context.fill(
            Path(ellipseIn: CGRect(x: 8, y: 20, width: 84, height: 80)),
            with: .radialGradient(
                Gradient(colors: [tint.opacity(isDelighted ? 0.34 : 0.22), tint.opacity(0)]),
                center: CGPoint(x: 50, y: 62),
                startRadius: 0,
                endRadius: 42
            )
        )
    }

    private func drawShadow(_ context: inout GraphicsContext) {
        let shrink = hop / 12
        context.fill(
            Path(ellipseIn: CGRect(x: 26 + shrink * 8, y: 91.5, width: 48 - shrink * 16, height: 7)),
            with: .radialGradient(
                Gradient(colors: [.black.opacity(0.5 - shrink * 0.2), .clear]),
                center: CGPoint(x: 50, y: 95),
                startRadius: 0,
                endRadius: 24
            )
        )
    }

    private func drawSparkles(_ context: inout GraphicsContext) {
        let spots: [(CGPoint, Double, Double)] = [
            (CGPoint(x: 22, y: 36), 0, 3.2),
            (CGPoint(x: 79, y: 28), 2.1, 2.6),
            (CGPoint(x: 80, y: 56), 4.0, 2.2),
            (CGPoint(x: 18, y: 60), 5.3, 1.8)
        ]
        for (center, phase, size) in spots {
            let twinkle = time == 0 ? 0.7 : max(sin(time * 1.8 + phase), 0)
            guard twinkle > 0.05 else { continue }
            let scale = size * twinkle
            var star = Path()
            star.move(to: CGPoint(x: center.x, y: center.y - scale))
            star.addQuadCurve(to: CGPoint(x: center.x + scale, y: center.y), control: center)
            star.addQuadCurve(to: CGPoint(x: center.x, y: center.y + scale), control: center)
            star.addQuadCurve(to: CGPoint(x: center.x - scale, y: center.y), control: center)
            star.addQuadCurve(to: CGPoint(x: center.x, y: center.y - scale), control: center)
            context.fill(star, with: .color(Color(red: 1, green: 0.95, blue: 0.75).opacity(0.85 * twinkle)))
        }
    }

    // MARK: Plant

    private struct Stem {
        var base: CGPoint
        var control: CGPoint
        var tip: CGPoint
        /// Radians from upright, positive leaning right.
        var tipAngle: Double

        func point(at t: Double) -> CGPoint {
            let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
            return CGPoint(
                x: a * base.x + b * control.x + c * tip.x,
                y: a * base.y + b * control.y + c * tip.y
            )
        }
    }

    private func stemGeometry() -> Stem {
        let base = CGPoint(x: 50, y: 59)
        let height = 26 + 10 * energy
        // A lively plant sways and leans a touch towards the pointer; a wilted
        // one barely stirs.
        let sway = sin(time * 1.5) * 0.05 * (0.3 + energy) + gaze.x * 0.1 * energy
        let lean = tiredness * tiredness * 1.3 + sway
        let tip = CGPoint(x: base.x + sin(lean) * height, y: base.y - cos(lean) * height)
        let control = CGPoint(x: base.x + sway * 8, y: base.y - height * 0.62)
        return Stem(base: base, control: control, tip: tip, tipAngle: lean)
    }

    private func drawStem(_ context: inout GraphicsContext, _ stem: Stem) {
        var path = Path()
        path.move(to: stem.base)
        path.addQuadCurve(to: stem.tip, control: stem.control)
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [leafColor(shade: -0.2), leafColor(shade: -0.04)]),
                startPoint: stem.base,
                endPoint: stem.tip
            ),
            style: StrokeStyle(lineWidth: 3.4, lineCap: .round)
        )
        context.stroke(
            path.offsetBy(dx: -0.8, dy: 0),
            with: .color(.white.opacity(0.2)),
            style: StrokeStyle(lineWidth: 0.9, lineCap: .round)
        )
    }

    private func drawLeaves(_ context: inout GraphicsContext, _ stem: Stem) {
        let flutter = sin(time * 2.1) * 0.07 * energy
        let droop = tiredness * 1.2
        // The lower pair is larger and opens wider; the upper pair is young.
        let pairs: [(t: Double, length: Double, spread: Double)] = [
            (0.34, 14 + 5 * energy, 0.36),
            (0.68, 10 + 3 * energy, 0.24)
        ]
        for (index, pair) in pairs.enumerated() {
            let attach = stem.point(at: pair.t)
            let wave = index == 0 ? flutter : -flutter
            let lean = stem.tipAngle * 0.5
            drawLeaf(&context, from: attach, angle: lean - .pi * pair.spread - droop + wave, length: pair.length)
            drawLeaf(&context, from: attach, angle: lean + .pi * pair.spread + droop - wave, length: pair.length)
        }
    }

    /// - Parameter angle: radians from upright.
    private func drawLeaf(_ context: inout GraphicsContext, from base: CGPoint, angle: Double, length: Double) {
        let direction = CGVector(dx: sin(angle), dy: -cos(angle))
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        let width = length * 0.4
        func at(_ t: Double, _ side: Double) -> CGPoint {
            CGPoint(
                x: base.x + direction.dx * length * t + normal.dx * width * side,
                y: base.y + direction.dy * length * t + normal.dy * width * side
            )
        }
        let tip = at(1, 0)

        // A little asymmetric, which is what keeps it from looking stamped.
        var leaf = Path()
        leaf.move(to: base)
        leaf.addCurve(to: tip, control1: at(0.12, 1.15), control2: at(0.72, 0.95))
        leaf.addCurve(to: base, control1: at(0.72, -0.75), control2: at(0.14, -0.7))
        context.fill(leaf, with: .linearGradient(
            Gradient(colors: [leafColor(shade: -0.14), leafColor(shade: 0.04), leafColor(shade: 0.16)]),
            startPoint: base,
            endPoint: tip
        ))

        var rib = Path()
        rib.move(to: at(0.05, 0))
        rib.addQuadCurve(to: at(0.85, 0.05), control: at(0.45, 0.12))
        context.stroke(rib, with: .color(.white.opacity(0.26)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))

        var sheen = Path()
        sheen.move(to: at(0.3, 0.5))
        sheen.addQuadCurve(to: at(0.72, 0.42), control: at(0.5, 0.62))
        context.stroke(sheen, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }

    /// A flower when thriving, a blushing bud when content, a closed bud
    /// when tired.
    private func drawCrown(_ context: inout GraphicsContext, _ stem: Stem) {
        let tip = stem.tip
        var crown = context
        crown.translateBy(x: tip.x, y: tip.y)
        crown.rotate(by: .radians(stem.tipAngle + sin(time * 1.2) * 0.06))

        switch mood {
        case .thriving:
            let bloom = 0.6 + 0.4 * min((energy - 0.7) / 0.25, 1) + (isDelighted ? 0.12 : 0)
            let length = 6.2 * bloom
            for index in 0..<6 {
                var petal = crown
                petal.rotate(by: .radians(Double(index) / 6 * 2 * .pi))
                let shape = Path(ellipseIn: CGRect(x: -2.4, y: -length - 0.6, width: 4.8, height: length + 1.2))
                petal.fill(shape, with: .linearGradient(
                    Gradient(colors: [Color(red: 1, green: 0.8, blue: 0.88), Color(red: 0.98, green: 0.47, blue: 0.66)]),
                    startPoint: CGPoint(x: 0, y: -length),
                    endPoint: .zero
                ))
            }
            crown.fill(
                Path(ellipseIn: CGRect(x: -2.9, y: -2.9, width: 5.8, height: 5.8)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 1, green: 0.93, blue: 0.55), Color(red: 0.98, green: 0.7, blue: 0.2)]),
                    center: CGPoint(x: -0.8, y: -0.8),
                    startRadius: 0,
                    endRadius: 3.4
                )
            )
            for angle in stride(from: 0.0, to: 2 * .pi, by: 2 * .pi / 5) {
                crown.fill(
                    Path(ellipseIn: CGRect(x: cos(angle) * 1.4 - 0.35, y: sin(angle) * 1.4 - 0.35, width: 0.7, height: 0.7)),
                    with: .color(Color(red: 0.75, green: 0.42, blue: 0.1).opacity(0.7))
                )
            }
        case .content:
            crown.fill(
                Path(ellipseIn: CGRect(x: -3.4, y: -7.4, width: 6.8, height: 8.4)),
                with: .color(leafColor(shade: 0.02))
            )
            crown.fill(
                Path(ellipseIn: CGRect(x: -2, y: -8, width: 4, height: 3.6)),
                with: .color(Color(red: 1, green: 0.6, blue: 0.75))
            )
        case .droopy, .wilting:
            crown.fill(
                Path(ellipseIn: CGRect(x: -2.9, y: -6.4, width: 5.8, height: 7.2)),
                with: .color(leafColor(shade: -0.04))
            )
        }
    }

    // MARK: Pot

    private var potBody: Path {
        var body = Path()
        body.move(to: CGPoint(x: 25, y: 64))
        body.addLine(to: CGPoint(x: 75, y: 64))
        body.addCurve(to: CGPoint(x: 66.5, y: 93), control1: CGPoint(x: 75.5, y: 76), control2: CGPoint(x: 71, y: 89))
        body.addQuadCurve(to: CGPoint(x: 33.5, y: 93), control: CGPoint(x: 50, y: 96.5))
        body.addCurve(to: CGPoint(x: 25, y: 64), control1: CGPoint(x: 29, y: 89), control2: CGPoint(x: 24.5, y: 76))
        body.closeSubpath()
        return body
    }

    private func drawPot(_ context: inout GraphicsContext) {
        let body = potBody
        context.fill(body, with: .linearGradient(
            Gradient(colors: [Self.terracotta, Self.terracottaDeep]),
            startPoint: CGPoint(x: 50, y: 64), endPoint: CGPoint(x: 50, y: 95)
        ))

        var inside = context
        inside.clip(to: body)
        // Lit from the upper left: sheen there, shade round the right.
        inside.fill(body, with: .linearGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0.22), location: 0),
                .init(color: .clear, location: 0.4),
                .init(color: .black.opacity(0.3), location: 1)
            ]),
            startPoint: CGPoint(x: 25, y: 74), endPoint: CGPoint(x: 75, y: 74)
        ))
        // The rim's shadow on the body.
        inside.fill(
            Path(CGRect(x: 20, y: 64, width: 60, height: 3.5)),
            with: .linearGradient(
                Gradient(colors: [.black.opacity(0.3), .clear]),
                startPoint: CGPoint(x: 50, y: 64), endPoint: CGPoint(x: 50, y: 67.5)
            )
        )
        // A painted band of dots round the foot.
        inside.fill(Path(CGRect(x: 20, y: 87, width: 60, height: 3)), with: .color(Self.terracottaDeep.opacity(0.75)))
        for x in stride(from: 29.0, through: 71.0, by: 6) {
            inside.fill(
                Path(ellipseIn: CGRect(x: x - 0.8, y: 87.7, width: 1.6, height: 1.6)),
                with: .color(Self.cream.opacity(0.85))
            )
        }
        // A glaze highlight down the lit side.
        inside.fill(
            Path(ellipseIn: CGRect(x: 27.4, y: 68, width: 5, height: 15)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.26), .white.opacity(0)]),
                center: CGPoint(x: 29.9, y: 72),
                startRadius: 0,
                endRadius: 8
            )
        )

        let rim = Path(roundedRect: CGRect(x: 21, y: 55.5, width: 58, height: 10), cornerRadius: 5)
        context.fill(rim, with: .linearGradient(
            Gradient(colors: [Self.terracottaLight, Self.terracotta, Self.terracottaDeep]),
            startPoint: CGPoint(x: 50, y: 55.5), endPoint: CGPoint(x: 50, y: 65.5)
        ))
        context.fill(rim, with: .linearGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0.16), location: 0),
                .init(color: .clear, location: 0.4),
                .init(color: .black.opacity(0.24), location: 1)
            ]),
            startPoint: CGPoint(x: 21, y: 60), endPoint: CGPoint(x: 79, y: 60)
        ))
        var lip = Path()
        lip.move(to: CGPoint(x: 26, y: 57))
        lip.addLine(to: CGPoint(x: 52, y: 57))
        context.stroke(lip, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.5), .white.opacity(0)]),
            startPoint: CGPoint(x: 26, y: 57), endPoint: CGPoint(x: 52, y: 57)
        ), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))

        // Soil, with a couple of pebbles catching the light.
        context.fill(
            Path(ellipseIn: CGRect(x: 25.5, y: 54.6, width: 49, height: 5.2)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.2, green: 0.12, blue: 0.09), Color(red: 0.33, green: 0.21, blue: 0.14)]),
                startPoint: CGPoint(x: 50, y: 54.6), endPoint: CGPoint(x: 50, y: 59.8)
            )
        )
        for pebble in [CGRect(x: 36, y: 56.4, width: 2.4, height: 1.3), CGRect(x: 60, y: 56.8, width: 1.8, height: 1.1)] {
            context.fill(Path(ellipseIn: pebble), with: .color(Color(red: 0.5, green: 0.36, blue: 0.27)))
        }
    }

    // MARK: Face

    private static let ink = Color(red: 0.17, green: 0.08, blue: 0.06)

    private func drawFace(_ context: inout GraphicsContext) {
        var face = context
        // The whole face turns a little towards the pointer.
        face.translateBy(x: gaze.x * 1.2, y: gaze.y * 0.8)

        drawCheeks(&face)
        for x in [41.5, 58.5] {
            if isDelighted {
                var arc = Path()
                arc.move(to: CGPoint(x: x - 3, y: 76.5))
                arc.addQuadCurve(to: CGPoint(x: x + 3, y: 76.5), control: CGPoint(x: x, y: 71))
                face.stroke(arc, with: .color(Self.ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            } else {
                drawEye(&face, x: x)
            }
        }
        if !isDelighted, mood == .droopy || mood == .wilting { drawBrows(&face) }
        drawMouth(&face)
    }

    private func drawEye(_ context: inout GraphicsContext, x: Double) {
        let blinkPhase = time.truncatingRemainder(dividingBy: 4.3)
        let isBlinking = time > 0 && blinkPhase < 0.13
        let lid: Double
        if isBlinking {
            lid = 0.12
        } else {
            switch mood {
            case .wilting: lid = 0.42
            case .droopy: lid = 0.68
            case .thriving, .content: lid = 1
            }
        }
        let width = 6.2, height = 7.4 * lid
        // Lids close from the top, so the eye keeps its bottom edge.
        let frame = CGRect(x: x - width / 2, y: 78.7 - height, width: width, height: height)
        context.fill(Path(ellipseIn: frame), with: .color(Self.ink))
        guard lid > 0.3 else { return }

        // Catchlights, which carry the gaze.
        let look = CGPoint(x: gaze.x * 0.9, y: gaze.y * 0.7)
        let big = CGRect(
            x: x - 1.9 + look.x,
            y: frame.minY + 1.1 + look.y * lid,
            width: 2.6,
            height: 2.6 * min(lid * 1.2, 1)
        )
        context.fill(Path(ellipseIn: big), with: .color(.white.opacity(0.95)))
        if lid > 0.6 {
            let small = CGRect(x: x + 1 + look.x, y: frame.maxY - 2.6, width: 1.2, height: 1.2)
            context.fill(Path(ellipseIn: small), with: .color(.white.opacity(0.7)))
        }
    }

    /// Raised at the middle, the way worry looks.
    private func drawBrows(_ context: inout GraphicsContext) {
        let lift = mood == .wilting ? 1.4 : 0.7
        for (outer, inner) in [(37.8, 44.6), (62.2, 55.4)] {
            var brow = Path()
            brow.move(to: CGPoint(x: outer, y: 70.6))
            brow.addLine(to: CGPoint(x: inner, y: 70.6 - lift))
            context.stroke(brow, with: .color(Self.ink.opacity(0.85)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
    }

    private func drawCheeks(_ context: inout GraphicsContext) {
        guard energy >= 0.45 || isDelighted else { return }
        var blush = context
        blush.addFilter(.blur(radius: 0.9))
        let strength = isDelighted ? 0.6 : 0.42
        for x in [34.2, 65.8] {
            blush.fill(
                Path(ellipseIn: CGRect(x: x - 3.6, y: 79.2, width: 7.2, height: 3.8)),
                with: .color(Color(red: 1, green: 0.48, blue: 0.52).opacity(strength))
            )
        }
    }

    private func drawMouth(_ context: inout GraphicsContext) {
        if isDelighted || mood == .thriving {
            // An open grin, with a tongue.
            let depth = isDelighted ? 6.6 : 5.2
            var mouth = Path()
            mouth.move(to: CGPoint(x: 45.2, y: 81.2))
            mouth.addQuadCurve(to: CGPoint(x: 54.8, y: 81.2), control: CGPoint(x: 50, y: 82))
            mouth.addQuadCurve(to: CGPoint(x: 45.2, y: 81.2), control: CGPoint(x: 50, y: 81.2 + depth * 1.3))
            mouth.closeSubpath()
            context.fill(mouth, with: .color(Self.ink))
            var tongue = context
            tongue.clip(to: mouth)
            tongue.fill(
                Path(ellipseIn: CGRect(x: 47, y: 81.2 + depth * 0.5, width: 6, height: 4)),
                with: .color(Color(red: 1, green: 0.47, blue: 0.5))
            )
            return
        }

        var mouth = Path()
        switch mood {
        case .content:
            mouth.move(to: CGPoint(x: 45.5, y: 82))
            mouth.addQuadCurve(to: CGPoint(x: 54.5, y: 82), control: CGPoint(x: 50, y: 85.6))
        case .droopy:
            mouth.move(to: CGPoint(x: 46.8, y: 83))
            mouth.addQuadCurve(to: CGPoint(x: 53.2, y: 83), control: CGPoint(x: 50, y: 82.4))
        case .wilting:
            // A wobbly frown.
            mouth.move(to: CGPoint(x: 45.5, y: 84.4))
            mouth.addCurve(
                to: CGPoint(x: 54.5, y: 84.4),
                control1: CGPoint(x: 47.5, y: 81),
                control2: CGPoint(x: 52.5, y: 81)
            )
        case .thriving:
            break
        }
        context.stroke(mouth, with: .color(Self.ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }

    private func drawSweat(_ context: inout GraphicsContext) {
        let slide = time == 0 ? 0 : (time * 0.5).truncatingRemainder(dividingBy: 1)
        var drop = context
        drop.opacity = 1 - max(slide - 0.7, 0) / 0.3
        let center = CGPoint(x: 66.5, y: 68 + slide * 4)
        drop.fill(Self.dropPath(center: center, size: 4.6), with: .linearGradient(
            Gradient(colors: [Color(red: 0.8, green: 0.95, blue: 1), Color(red: 0.45, green: 0.75, blue: 1)]),
            startPoint: CGPoint(x: center.x, y: center.y - 3), endPoint: CGPoint(x: center.x, y: center.y + 2)
        ))
    }

    // MARK: Particles

    /// Every few seconds a dry leaf lets go and drifts down.
    private func drawFallingLeaf(_ context: inout GraphicsContext, from tip: CGPoint) {
        let cycle = 5.5
        let progress = time.truncatingRemainder(dividingBy: cycle) / cycle
        guard progress < 0.75 else { return }
        let fall = progress / 0.75
        let position = CGPoint(
            x: tip.x + 4 + fall * 8 + sin(fall * 9) * 3,
            y: tip.y + 2 + fall * 30
        )
        var leaf = context
        leaf.opacity = 1 - max(fall - 0.6, 0) / 0.4
        leaf.translateBy(x: position.x, y: position.y)
        leaf.rotate(by: .radians(fall * 5))
        leaf.fill(
            Path(ellipseIn: CGRect(x: -2.6, y: -1.2, width: 5.2, height: 2.4)),
            with: .color(Color(red: 0.7, green: 0.55, blue: 0.3))
        )
    }

    private func drawThirstDrop(_ context: inout GraphicsContext) {
        let bob = sin(time * 2.4) * 1.3
        let center = CGPoint(x: 82, y: 44 + bob)
        context.fill(Self.dropPath(center: center, size: 9), with: .linearGradient(
            Gradient(colors: [Color(red: 0.62, green: 0.88, blue: 1.0), Color(red: 0.2, green: 0.55, blue: 0.96)]),
            startPoint: CGPoint(x: center.x, y: center.y - 5),
            endPoint: CGPoint(x: center.x, y: center.y + 4)
        ))
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 0.6, width: 1.5, height: 2.2)),
            with: .color(.white.opacity(0.75))
        )
    }

    private func drawSplash(_ context: inout GraphicsContext, progress: Double) {
        let fade = 1 - max(progress - 0.75, 0) / 0.25
        for (index, x) in [41.0, 50.0, 59.0].enumerated() {
            let delay = Double(index) * 0.12
            let local = min(max((progress - delay) / (1 - delay), 0), 1)
            let fall = local * local
            let center = CGPoint(x: x, y: 16 + fall * 40)
            context.fill(
                Self.dropPath(center: center, size: 6),
                with: .color(Color(red: 0.45, green: 0.78, blue: 1.0).opacity(fade))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 1.4, y: center.y - 0.4, width: 1, height: 1.5)),
                with: .color(.white.opacity(0.7 * fade))
            )
        }
    }

    /// Hearts float up from the plant when the buddy is pleased.
    private func drawHearts(_ context: inout GraphicsContext, progress: Double) {
        for index in 0..<3 {
            let delay = Double(index) * 0.13
            let local = min(max((progress - delay) / 0.7, 0), 1)
            guard local > 0, local < 1 else { continue }
            let center = CGPoint(
                x: 50 + Double(index - 1) * 13 + sin(local * 6 + Double(index)) * 2,
                y: 40 - local * 22
            )
            let size = 4.2 * min(local * 4, 1)
            var heart = context
            heart.opacity = 1 - max(local - 0.55, 0) / 0.45
            heart.fill(Self.heartPath(center: center, size: size), with: .linearGradient(
                Gradient(colors: [Color(red: 1, green: 0.6, blue: 0.7), Color(red: 0.96, green: 0.3, blue: 0.48)]),
                startPoint: CGPoint(x: center.x, y: center.y - size),
                endPoint: CGPoint(x: center.x, y: center.y + size)
            ))
        }
    }

    // MARK: Colour

    private static let terracottaLight = Color(red: 0.95, green: 0.62, blue: 0.46)
    private static let terracotta = Color(red: 0.86, green: 0.48, blue: 0.34)
    private static let terracottaDeep = Color(red: 0.6, green: 0.29, blue: 0.2)
    private static let cream = Color(red: 1, green: 0.92, blue: 0.8)

    private var moodTint: Color {
        switch mood {
        case .thriving: return Color(red: 0.55, green: 0.95, blue: 0.6)
        case .content: return Color(red: 0.7, green: 0.9, blue: 0.45)
        case .droopy: return Color(red: 1, green: 0.76, blue: 0.32)
        case .wilting: return Color(red: 1, green: 0.45, blue: 0.35)
        }
    }

    /// Fresh green at full energy, through olive, to dry straw.
    private func leafColor(shade: Double) -> Color {
        let fresh = (0.32, 0.8, 0.44)
        let tired = (0.74, 0.71, 0.32)
        let spent = (0.62, 0.47, 0.26)
        let rgb: (Double, Double, Double)
        if energy >= 0.5 {
            rgb = Self.mix(tired, fresh, (energy - 0.5) / 0.5)
        } else {
            rgb = Self.mix(spent, tired, energy / 0.5)
        }
        func adjust(_ value: Double) -> Double { min(max(value + shade, 0), 1) }
        return Color(red: adjust(rgb.0), green: adjust(rgb.1), blue: adjust(rgb.2))
    }

    private static func mix(
        _ a: (Double, Double, Double),
        _ b: (Double, Double, Double),
        _ t: Double
    ) -> (Double, Double, Double) {
        let t = min(max(t, 0), 1)
        return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }

    // MARK: Shapes

    private static func dropPath(center: CGPoint, size: Double) -> Path {
        var path = Path()
        let radius = size * 0.42
        path.move(to: CGPoint(x: center.x, y: center.y - size * 0.62))
        path.addQuadCurve(
            to: CGPoint(x: center.x + radius, y: center.y + size * 0.05),
            control: CGPoint(x: center.x + radius * 0.35, y: center.y - size * 0.3)
        )
        path.addArc(
            center: CGPoint(x: center.x, y: center.y + size * 0.05),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y - size * 0.62),
            control: CGPoint(x: center.x - radius * 0.35, y: center.y - size * 0.3)
        )
        return path
    }

    private static func heartPath(center: CGPoint, size: Double) -> Path {
        var path = Path()
        let bottom = CGPoint(x: center.x, y: center.y + size)
        path.move(to: bottom)
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y - size * 0.45),
            control1: CGPoint(x: center.x - size * 1.6, y: center.y - size * 0.1),
            control2: CGPoint(x: center.x - size * 0.6, y: center.y - size * 1.3)
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: center.x + size * 0.6, y: center.y - size * 1.3),
            control2: CGPoint(x: center.x + size * 1.6, y: center.y - size * 0.1)
        )
        return path
    }
}
