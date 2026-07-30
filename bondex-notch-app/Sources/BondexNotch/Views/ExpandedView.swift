import SwiftUI

/// The full panel: a tab strip along the top and one widget below it.
struct ExpandedView: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var notch: NotchViewModel
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        self.environment = environment
        self.notch = environment.notch
        self.settings = environment.settings
    }

    private var accent: Color { settings.effectiveAccent.color }

    /// Keeps the tab strip clear of the hardware notch, which sits over the top
    /// centre of the panel.
    private var topInset: CGFloat { notch.geometry.notchSize.height + 4 }

    var body: some View {
        VStack(spacing: 10) {
            header
            Divider().overlay(Theme.hairline)
            widget
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, topInset)
        .padding(.horizontal, Theme.contentPadding)
        .padding(.bottom, 12)
        .foregroundStyle(Theme.primaryText)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            ForEach(environment.availableTabs) { tab in
                TabChip(
                    tab: tab,
                    isSelected: notch.tab == tab,
                    isLocked: tab.requiredFeature.map { !settings.isUnlocked($0) } ?? false,
                    accent: accent
                ) {
                    withAnimation(Motion.content(settings.motion)) { notch.tab = tab }
                }
            }

            Spacer(minLength: 6)

            NotchButton(systemImage: "xmark", size: 10, tint: Theme.secondaryText) {
                notch.collapse()
            }
        }
    }

    // MARK: Widget

    @ViewBuilder
    private var widget: some View {
        if let feature = notch.tab.requiredFeature, !settings.isUnlocked(feature) {
            LockedFeatureView(feature: feature, tint: accent)
        } else {
            switch notch.tab {
            case .home:
                HomeWidget(environment: environment)
            case .music:
                MusicWidget(environment: environment)
            case .files:
                FileActivityWidget(environment: environment)
            case .activity:
                ActivityWidget(environment: environment)
            case .shelf:
                ShelfWidget(environment: environment)
            }
        }
    }
}

// MARK: - Tab chip

private struct TabChip: View {
    let tab: NotchTab
    let isSelected: Bool
    let isLocked: Bool
    let accent: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isLocked ? "lock.fill" : tab.systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                if isSelected {
                    Text(tab.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .fixedSize()
                }
            }
            .foregroundStyle(isSelected ? Color.black : Theme.secondaryText)
            .padding(.horizontal, isSelected ? 9 : 7)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous).fill(
                    isSelected
                        ? AnyShapeStyle(accent)
                        : AnyShapeStyle(Color.white.opacity(isHovering ? 0.14 : 0.06))
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
