import SwiftUI

// MARK: - Offscreen rendering

private struct OffscreenRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the view tree is being rasterised by `ImageRenderer` rather
    /// than shown on screen.
    var isRenderingOffscreen: Bool {
        get { self[OffscreenRenderKey.self] }
        set { self[OffscreenRenderKey.self] = newValue }
    }
}

/// A scroll container that collapses to a plain stack when rendered offscreen.
///
/// `ImageRenderer` rasterises `ScrollView` as empty, which would make every
/// list widget invisible in the preview tool. On screen this is an ordinary
/// `ScrollView`.
struct ScrollingStack<Content: View>: View {
    var axis: Axis.Set = .vertical
    var spacing: CGFloat = 6
    @ViewBuilder var content: () -> Content

    @Environment(\.isRenderingOffscreen) private var isRenderingOffscreen

    var body: some View {
        if isRenderingOffscreen {
            // `Color.clear` takes exactly the space the parent offers and the
            // overlay does not feed its own size back, so an over-long stack
            // is clipped instead of stretching the panel.
            Color.clear
                .overlay(alignment: .topLeading) { stack }
                .clipped()
        } else {
            ScrollView(axis, showsIndicators: false) { stack }
                .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private var stack: some View {
        if axis == .horizontal {
            HStack(spacing: spacing, content: content)
        } else {
            VStack(spacing: spacing, content: content)
        }
    }
}

// MARK: - Measurement

/// Reports a view's width without writing state during layout.
///
/// Setting `@State` from inside a `GeometryReader`'s body — the usual shortcut —
/// mutates the graph in the middle of the layout pass that produced the value,
/// which costs an extra pass every time and reliably produces visible jitter in a
/// view that is also animating. A preference carries the measurement up to the
/// parent after layout has finished instead.
private struct WidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Marquee

/// Scrolls text horizontally when it does not fit, and stays still when it does.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 12, weight: .semibold)
    var speed: Double = 26   // points per second
    /// Caps the width and lets the view hug shorter text instead of filling the
    /// space it is offered. Needed wherever the title sits next to something else
    /// that should stay beside it — the peek strip's equaliser, for one. Leave
    /// `nil` to take all the width available.
    var maxWidth: CGFloat?

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    /// What the running animation was started for. The scroll is a
    /// `repeatForever` animation, so restarting it when nothing has actually
    /// changed makes the text visibly jump back to the start — which is what
    /// happens on every re-render while the panel is animating.
    @State private var runningKey: String?

    private var overflows: Bool { textWidth > containerWidth + 1 }
    private var gap: CGFloat { 34 }

    /// Identifies a distinct scroll: same text at the same size in the same box
    /// means the animation already on screen is the right one.
    private var animationKey: String {
        "\(text)|\(Int(textWidth.rounded()))|\(Int(containerWidth.rounded()))"
    }

    var body: some View {
        HStack(spacing: gap) {
            content
            if overflows { content }
        }
        .offset(x: offset)
        .modifier(MarqueeWidth(maxWidth: maxWidth, textWidth: textWidth))
        .frame(height: 16)
        .clipped()
        .modifier(EdgeFadeIfOverflowing(isActive: overflows))
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: WidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(WidthKey.self) { width in
            containerWidth = width
        }
        .onChange(of: animationKey) { _, _ in syncAnimation() }
        .onAppear { syncAnimation() }
    }

    private var content: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .task(id: proxy.size.width) { textWidth = proxy.size.width }
                }
            )
    }

    private func syncAnimation() {
        guard runningKey != animationKey else { return }
        runningKey = animationKey

        guard overflows else {
            withAnimation(.easeOut(duration: 0.15)) { offset = 0 }
            return
        }

        let distance = textWidth + gap
        // Reset without animating, then start the loop, so the text does not
        // slide backwards into position first.
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { offset = 0 }

        withAnimation(
            .linear(duration: distance / speed)
                .delay(1.2)
                .repeatForever(autoreverses: false)
        ) {
            offset = -distance
        }
    }
}

/// Either fills the offered width, or hugs the text up to a cap.
private struct MarqueeWidth: ViewModifier {
    let maxWidth: CGFloat?
    let textWidth: CGFloat

    func body(content: Content) -> some View {
        if let maxWidth {
            // Before the first measurement, claim the full cap; anything narrower
            // would make a long title decide it fits and never scroll.
            let width = textWidth > 0 ? min(textWidth, maxWidth) : maxWidth
            content.frame(width: width, alignment: .leading)
        } else {
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The fade is only correct while the text is actually scrolling; on a title that
/// fits, fading the last few points of a short word looks like a rendering bug.
private struct EdgeFadeIfOverflowing: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.edgeFade(10)
        } else {
            content
        }
    }
}

// MARK: - Audio bars

/// Idle animation that reads as "audio is playing" without needing real FFT data,
/// which no public macOS API exposes for another app's output.
///
/// Each bar is one `repeatForever` scale animation rather than a `TimelineView`
/// recomputing heights every frame. That distinction is not cosmetic: this view
/// sits in the peek, which is on screen for as long as anything is playing, and
/// driving it from a timeline measured **~10% CPU continuously** — a timeline tick
/// re-evaluates the body, which re-renders the whole panel. Handing four looping
/// animations to Core Animation instead costs the app nothing between state
/// changes, because the render server interpolates them.
///
/// The bars use durations that share no common multiple, so they drift in and out
/// of phase instead of visibly repeating in lockstep.
struct AudioBars: View {
    var isAnimating: Bool
    var tint: Color
    var barCount: Int = 4

    @Environment(\.isRenderingOffscreen) private var isRenderingOffscreen

    var body: some View {
        if isRenderingOffscreen {
            // `ImageRenderer` cannot rasterise an `NSViewRepresentable`; the
            // preview tool gets a still of the bars instead.
            HStack(alignment: .center, spacing: AudioBarMetrics.spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(
                            width: AudioBarMetrics.barWidth,
                            height: AudioBarMetrics.height * AudioBarMetrics.resting(index)
                        )
                }
            }
            .frame(height: AudioBarMetrics.height)
        } else {
            AudioBarLayers(isAnimating: isAnimating, tint: tint, barCount: barCount)
                .frame(
                    width: AudioBarMetrics.width(barCount: barCount),
                    height: AudioBarMetrics.height
                )
        }
    }
}

private enum AudioBarMetrics {
    static let barWidth: CGFloat = 2.5
    static let spacing: CGFloat = 2
    static let height: CGFloat = 14

    /// Durations that share no common multiple, so the bars drift in and out of
    /// phase instead of visibly repeating in lockstep.
    static let durations: [Double] = [0.62, 0.43, 0.78, 0.51]
    static func duration(_ index: Int) -> Double { durations[index % durations.count] }

    private static let restingScales: [CGFloat] = [0.24, 0.42, 0.18, 0.33]
    static func resting(_ index: Int) -> CGFloat { restingScales[index % restingScales.count] }

    static func width(barCount: Int) -> CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(max(barCount - 1, 0)) * spacing
    }
}

/// The bars as detached Core Animation layers.
///
/// Every SwiftUI expression of this — a `TimelineView` recomputing heights, or a
/// `repeatForever` `scaleEffect` — keeps the animation on the display cycle,
/// re-entering the transaction machinery every frame. Measured on the running
/// app, either cost **5–10% CPU continuously**, and the peek is on screen for as
/// long as anything is playing. A `CABasicAnimation` installed on a layer is
/// interpolated by the render server instead: once added, the app does no work
/// per frame at all.
private struct AudioBarLayers: NSViewRepresentable {
    var isAnimating: Bool
    var tint: Color
    var barCount: Int

    func makeNSView(context: Context) -> AudioBarView {
        AudioBarView(barCount: barCount)
    }

    func updateNSView(_ view: AudioBarView, context: Context) {
        view.update(tint: NSColor(tint), isAnimating: isAnimating)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AudioBarView, context: Context)
    -> CGSize? {
        CGSize(
            width: AudioBarMetrics.width(barCount: barCount),
            height: AudioBarMetrics.height
        )
    }
}

final class AudioBarView: NSView {

    private var bars: [CALayer] = []
    private var isAnimating = false
    private var tint: NSColor = .white

    init(barCount: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        for _ in 0..<barCount {
            let bar = CALayer()
            bar.cornerRadius = AudioBarMetrics.barWidth / 2
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: AudioBarMetrics.width(barCount: bars.count),
            height: AudioBarMetrics.height
        )
    }

    override func layout() {
        super.layout()
        // Layout is not an animation; without this the bars would slide into
        // position whenever the panel resizes around them.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(
                x: 0, y: 0,
                width: AudioBarMetrics.barWidth,
                height: AudioBarMetrics.height
            )
            bar.position = CGPoint(
                x: CGFloat(index) * (AudioBarMetrics.barWidth + AudioBarMetrics.spacing)
                    + AudioBarMetrics.barWidth / 2,
                y: bounds.midY
            )
        }
        CATransaction.commit()
    }

    func update(tint newTint: NSColor, isAnimating playing: Bool) {
        if newTint != tint {
            tint = newTint
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bars.forEach { $0.backgroundColor = newTint.cgColor }
            CATransaction.commit()
        }

        guard playing != isAnimating else { return }
        isAnimating = playing
        playing ? start() : stop()
    }

    private func start() {
        for (index, bar) in bars.enumerated() {
            let resting = AudioBarMetrics.resting(index)

            let pulse = CABasicAnimation(keyPath: "transform.scale.y")
            pulse.fromValue = resting
            pulse.toValue = 1
            pulse.duration = AudioBarMetrics.duration(index)
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            bar.setValue(resting, forKeyPath: "transform.scale.y")
            bar.add(pulse, forKey: "pulse")
        }
    }

    private func stop() {
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "pulse")
            // Settle flat rather than freezing mid-bounce at whatever height the
            // loop happened to have reached.
            let settle = CABasicAnimation(keyPath: "transform.scale.y")
            settle.duration = 0.18
            settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bar.add(settle, forKey: "settle")
            bar.setValue(AudioBarMetrics.resting(index), forKeyPath: "transform.scale.y")
        }
    }
}

// MARK: - Meters

/// Thin capsule meter used by the system widget.
struct MeterBar: View {
    var value: Double        // 0...1
    var tint: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.width * min(max(value, 0), 1), value > 0 ? 3 : 0))
            }
        }
        .frame(height: height)
    }
}

/// Circular gauge for CPU/memory.
struct ProgressRing: View {
    var value: Double
    var tint: Color
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Artwork

/// Album art with a graceful placeholder — artwork is frequently missing for
/// streamed or locally imported tracks.
struct ArtworkView: View {
    var image: NSImage?
    var cornerRadius: CGFloat = 8
    var tint: Color

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [tint.opacity(0.55), tint.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Controls

/// Borderless icon button tuned for the panel: no focus ring, no blue tint,
/// and a hover state that works in a non-key window.
struct NotchButton: View {
    let systemImage: String
    var size: CGFloat = 13
    var isProminent = false
    var tint: Color = .white
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isProminent ? Color.black : tint)
                .frame(width: size + 15, height: size + 15)
                .background(
                    Circle().fill(
                        isProminent
                            ? AnyShapeStyle(tint)
                            : AnyShapeStyle(Color.white.opacity(isHovering ? 0.16 : 0.0))
                    )
                )
                .contentShape(Circle())
                // A touch of give on press. Transport controls are the only thing
                // in the panel that gets clicked repeatedly, so they are worth
                // making feel like buttons.
                .scaleEffect(isPressed ? 0.9 : 1)
                .animation(Motion.hover, value: isHovering)
                .animation(.spring(duration: 0.22, bounce: 0.35), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

/// Empty-state block reused by every widget.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.tertiaryText)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown in place of a widget the current tier does not include.
struct LockedFeatureView: View {
    let feature: ProFeature
    var tint: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(feature.displayName) is a Pro feature")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.primaryText)
            Text("Add your license key in Settings to unlock it.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
