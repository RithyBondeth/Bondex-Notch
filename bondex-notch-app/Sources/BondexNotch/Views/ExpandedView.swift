import SwiftUI

/// Carries the expanded content's laid-out height up to the panel.
struct ExpandedHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The full panel: a tab strip along the top and one widget below it.
struct ExpandedView: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var notch: NotchViewModel
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var commandPalette: CommandPaletteService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.notch = environment.notch
        self.settings = environment.settings
        self.commandPalette = environment.commandPalette
    }

    private var accent: Color { settings.effectiveAccentColor }

    private var notchWidth: CGFloat { notch.geometry.notchSize.width }

    /// The band the hardware notch hangs into. Its height is the notch's, so
    /// controls placed beside the notch line up with the menu bar items they
    /// replace.
    private var topBandHeight: CGFloat { max(notch.geometry.notchSize.height, 24) }

    /// Room either side of the notch inside the content padding.
    private var wingWidth: CGFloat {
        max((notch.contentSize.width - notchWidth) / 2 - Theme.contentPadding, 0)
    }

    var body: some View {
        VStack(spacing: 6) {
            topBand

            VStack(spacing: 8) {
                if commandPalette.isPresented {
                    CommandPaletteView(environment: environment)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else {
                    tabStrip
                    // A system `Divider` renders as a light separator tuned for a light
                    // window; on a near-black panel it reads as a bright scratch.
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, Theme.hairline, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(height: 1)
                    widget
                        .frame(maxWidth: .infinity)
                        // nil height means "as tall as the content" — that is what makes
                        // the panel itself size to what it is showing.
                        .frame(height: notch.tab.widgetHeight)
                        // Swapping tabs is a content change, so it gets the content
                        // curve rather than the panel's.
                        .animation(Motion.content(settings.motion), value: notch.tab)
                }
            }
        }
        .padding(.horizontal, Theme.contentPadding)
        .padding(.bottom, Theme.contentPadding)
        .foregroundStyle(Theme.primaryText)
        // Report the height this content actually needs, so the panel can be
        // drawn at exactly that size rather than at a one-size-fits-all maximum.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ExpandedHeightKey.self, value: proxy.size.height)
            }
        )
    }

    // MARK: Top band

    /// The strip either side of the hardware notch.
    ///
    /// It used to be left empty — a black band the height of the menu bar above
    /// a header row that had to carry the tabs *and* every control. The panel
    /// controls live beside the notch now, where the menu bar items they cover
    /// were, and the tab strip gets a row to itself.
    private var topBand: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                NotchButton(systemImage: "gearshape.fill", size: 9, tint: Theme.secondaryText) {
                    notch.collapse()
                    environment.requestSettingsPage?(.general)
                }
                .help("Settings")
                .accessibilityLabel("Open Settings")

                if let profile = settings.activeProfile {
                    Image(systemName: profile.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(accent.opacity(0.14)))
                        .overlay(Circle().strokeBorder(accent.opacity(0.25), lineWidth: 0.7))
                        .help("\(profile.displayName) profile active")
                        .accessibilityLabel("\(profile.displayName) profile active")
                        .transition(.scale.combined(with: .opacity))
                }

                if environment.privacyActivity.state.isActive {
                    PrivacyActivityMarks(state: environment.privacyActivity.state)
                        .help(environment.privacyActivity.state.accessibilityValue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: wingWidth, alignment: .leading)

            // Reserved for the hardware notch.
            Color.clear.frame(width: notchWidth)

            HStack(spacing: 6) {
                NotchButton(
                    systemImage: "magnifyingglass",
                    size: 9,
                    tint: commandPalette.isPresented ? accent : Theme.secondaryText
                ) {
                    if commandPalette.isPresented {
                        commandPalette.dismiss()
                    } else {
                        environment.presentCommandPalette()
                    }
                }
                .help("Command Palette (\(settings.preferences.commandPaletteShortcut.displayName))")
                .accessibilityLabel(
                    commandPalette.isPresented ? "Close Command Palette" : "Open Command Palette"
                )

                NotchButton(systemImage: "xmark", size: 9, tint: Theme.secondaryText) {
                    notch.collapse()
                }
                .help("Close")
                .accessibilityLabel("Close notch")
            }
            .frame(width: wingWidth, alignment: .trailing)
        }
        .frame(height: topBandHeight)
        .animation(Motion.content(settings.motion), value: settings.activeProfile?.id)
        .animation(
            Motion.content(settings.motion),
            value: environment.privacyActivity.state.isActive
        )
    }

    // MARK: Tabs

    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(environment.availableTabs) { tab in
                TabChip(
                    tab: tab,
                    isSelected: notch.tab == tab,
                    accent: accent
                ) {
                    withAnimation(Motion.content(settings.motion)) { notch.tab = tab }
                }
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.045), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.7)
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: Widget

    @ViewBuilder
    private var widget: some View {
        switch notch.tab {
        case .home:
            HomeWidget(environment: environment)
        case .agents:
            AgentUsageWidget(environment: environment)
        case .capture:
            QuickCaptureWidget(environment: environment)
        case .shortcuts:
            CustomShortcutsWidget(environment: environment)
        case .music:
            MusicWidget(environment: environment)
        case .system:
            SystemWidget(environment: environment)
        case .live:
            LiveActivityWidget(environment: environment)
        case .files:
            FileActivityWidget(environment: environment)
        case .activity:
            ActivityWidget(environment: environment)
        case .clipboard:
            ClipboardWidget(environment: environment)
        case .shelf:
            ShelfWidget(environment: environment)
        }
    }
}

// MARK: - Tab chip

private struct TabChip: View {
    let tab: NotchTab
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                SymbolIcon(name: tab.systemImage, size: 9, weight: .semibold)
                    .foregroundStyle(isSelected ? accent : Theme.secondaryText)
                if isSelected {
                    Text(tab.title)
                        .font(.system(size: 10, weight: .semibold))
                        .fixedSize()
                        // Width, not opacity: the label has to push the
                        // neighbouring chips aside as it appears, or the strip
                        // jumps a whole label's width in one frame.
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(Motion.hover.delay(0.06)),
                                removal: .opacity.animation(.linear(duration: 0.05))
                            )
                        )
                }
            }
            .foregroundStyle(isSelected ? Theme.primaryText : Theme.secondaryText)
            .padding(.horizontal, isSelected ? 8 : 6)
            .padding(.vertical, 4.5)
            .background(
                Capsule(style: .continuous).fill(
                    isSelected
                        ? AnyShapeStyle(accent.opacity(0.17))
                        : AnyShapeStyle(Color.white.opacity(isHovering ? 0.09 : 0))
                )
            )
            .overlay(
                Capsule(style: .continuous).strokeBorder(
                    isFocused
                        ? Color.white.opacity(0.9)
                        : (isSelected ? accent.opacity(0.32) : .clear),
                    lineWidth: isFocused ? 2 : 0.7
                )
            )
            .shadow(color: isSelected ? accent.opacity(0.13) : .clear, radius: 7)
            .contentShape(Capsule())
            .animation(Motion.hover, value: isHovering)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
