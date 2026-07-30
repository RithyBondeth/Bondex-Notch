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

// MARK: - Marquee

/// Scrolls text horizontally when it does not fit, and stays still when it does.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 12, weight: .semibold)
    var speed: Double = 26   // points per second

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflows: Bool { textWidth > containerWidth + 1 }
    private var gap: CGFloat { 34 }

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.width
            HStack(spacing: gap) {
                content
                if overflows { content }
            }
            .offset(x: offset)
            .frame(width: available, alignment: .leading)
            .clipped()
            .onAppear { containerWidth = available; restart() }
            .onChange(of: available) { _, new in containerWidth = new; restart() }
            .onChange(of: text) { _, _ in restart() }
            .onChange(of: textWidth) { _, _ in restart() }
        }
        .frame(height: 16)
    }

    private var content: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear.onAppear { textWidth = proxy.size.width }
                }
            )
    }

    private func restart() {
        offset = 0
        guard overflows else { return }
        let distance = textWidth + gap
        withAnimation(
            .linear(duration: distance / speed).repeatForever(autoreverses: false)
        ) {
            offset = -distance
        }
    }
}

// MARK: - Audio bars

/// Idle animation that reads as "audio is playing" without needing real FFT
/// data, which no public macOS API exposes for another app's output.
struct AudioBars: View {
    var isAnimating: Bool
    var tint: Color
    var barCount: Int = 4

    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isAnimating)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: 2.5, height: height(for: index, at: t))
                }
            }
            .frame(height: 14)
        }
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        guard isAnimating else { return 3 }
        // Offset each bar so they never move in lockstep.
        let seed = Double(index) * 1.7
        let wave = sin(time * 5.4 + seed) * 0.5 + sin(time * 3.1 + seed * 2.3) * 0.5
        return 3 + CGFloat(abs(wave)) * 11
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
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
