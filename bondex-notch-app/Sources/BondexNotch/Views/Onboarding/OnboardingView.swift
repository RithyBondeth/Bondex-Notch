import SwiftUI

enum OnboardingPage: Int, CaseIterable {
    case basics
    case features
    case ready
}

/// The first-launch welcome: how to use the notch, what it should show, and a
/// chance to try it.
///
/// It exists so that a new user's first sight of Bondex is an explanation
/// rather than a stack of macOS permission dialogs. Nothing that raises one has
/// started yet (see `AppEnvironment.applyWidgetActivation`); the features page
/// says what each choice will ask for, and only the chosen ones start once it
/// is confirmed.
struct OnboardingView: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var settings: SettingsStore

    @State private var page: OnboardingPage
    @State private var choices: OnboardingChoices
    @State private var hasAppliedChoices = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onFinish: () -> Void

    init(
        environment: AppEnvironment,
        initialPage: OnboardingPage = .basics,
        onFinish: @escaping () -> Void
    ) {
        self.environment = environment
        self.settings = environment.settings
        self.onFinish = onFinish
        _page = State(initialValue: initialPage)
        _choices = State(initialValue: OnboardingChoices(preferences: environment.settings.preferences))
    }

    private var accent: Color { settings.effectiveAccentColor }

    /// Tall enough for every feature row without scrolling.
    static let size = CGSize(width: 580, height: 630)

    var body: some View {
        ZStack {
            backdrop

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 22)

                Group {
                    switch page {
                    case .basics: basics
                    case .features: features
                    case .ready: ready
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(page)
                .transition(pageTransition)

                footer
                    .padding(.top, 18)
            }
            .padding(.horizontal, 30)
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .preferredColorScheme(.dark)
        .tint(accent)
    }

    // MARK: Chrome

    private var backdrop: some View {
        ZStack {
            Color(red: 0.055, green: 0.06, blue: 0.075)
            RadialGradient(
                colors: [accent.opacity(0.16), accent.opacity(0.04), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            BondexLogoMark()
                .frame(width: 34, height: 34)
                .shadow(color: accent.opacity(0.3), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch page {
        case .basics: return "Welcome to Bondex Notch"
        case .features: return "Choose what it shows"
        case .ready: return "You're set"
        }
    }

    private var subtitle: String {
        switch page {
        case .basics:
            return "It lives in your notch and the menu bar. Three things to know."
        case .features:
            return "Change any of these later in Settings. Nothing asks for access until you continue."
        case .ready:
            return "Settings, this tour and Quit are in the menu bar."
        }
    }

    private var footer: some View {
        HStack {
            if page != .basics {
                Button("Back") { go(to: page.rawValue - 1) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(OnboardingPage.allCases, id: \.self) { candidate in
                    Capsule()
                        .fill(candidate == page ? accent : Color.white.opacity(0.18))
                        .frame(width: candidate == page ? 16 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(page.rawValue + 1) of \(OnboardingPage.allCases.count)")

            Spacer()

            Button(primaryTitle) { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var primaryTitle: String {
        switch page {
        case .basics: return "Continue"
        case .features: return "Turn these on"
        case .ready: return "Done"
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: 18).combined(with: .opacity),
            removal: .opacity
        )
    }

    private func go(to index: Int) {
        guard let next = OnboardingPage(rawValue: index) else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.05)) { page = next }
    }

    private func advance() {
        switch page {
        case .basics:
            go(to: OnboardingPage.features.rawValue)
        case .features:
            // The permission prompts for the chosen features follow this
            // click — the one moment they have just been explained.
            environment.completeOnboarding(choices)
            hasAppliedChoices = true
            go(to: OnboardingPage.ready.rawValue)
        case .ready:
            if !hasAppliedChoices, environment.needsOnboarding {
                environment.completeOnboarding(choices)
            }
            onFinish()
        }
    }

    // MARK: Basics

    private var basics: some View {
        VStack(alignment: .leading, spacing: 18) {
            NotchIllustration(accent: accent)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

            OnboardingRow(
                systemImage: "cursorarrow.rays",
                accent: accent,
                title: "Hover the notch to open it",
                detail: "Rest the pointer at the top centre of the screen. Move away and it closes."
            )
            OnboardingRow(
                systemImage: "cursorarrow.click.2",
                accent: accent,
                title: "Click to keep it open",
                detail: "Click the notch or the open panel to pin it. Click anywhere else, or press Esc, to close."
            )
            OnboardingRow(
                systemImage: "keyboard",
                accent: accent,
                title: "Open it from anywhere",
                detail: shortcutDetail
            ) {
                if settings.preferences.globalHotKeyEnabled {
                    KeyCaps(shortcut: settings.preferences.globalShortcut.displayName)
                }
            }
        }
    }

    private var shortcutDetail: String {
        var parts: [String] = []
        if settings.preferences.quickCaptureHotKeyEnabled {
            parts.append("\(settings.preferences.quickCaptureShortcut.displayName) captures a note")
        }
        if settings.preferences.commandPaletteHotKeyEnabled {
            parts.append("\(settings.preferences.commandPaletteShortcut.displayName) opens the command palette")
        }
        let extras = parts.joined(separator: ", ")
        return extras.isEmpty
            ? "Use the shortcut from any app; Left and Right Arrow switch tabs."
            : "From any app. \(extras.prefix(1).uppercased() + extras.dropFirst())."
    }

    // MARK: Features

    private var features: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(OnboardingFeature.all) { feature in
                    FeatureChoiceRow(
                        feature: feature,
                        accent: accent,
                        isOn: binding(feature.choice),
                        isAvailable: feature.id != "notifications" || choices.agents
                    )
                }
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<OnboardingChoices, Bool>) -> Binding<Bool> {
        Binding(get: { choices[keyPath: keyPath] }, set: { choices[keyPath: keyPath] = $0 })
    }

    // MARK: Ready

    private var ready: some View {
        VStack(alignment: .leading, spacing: 14) {
            readyCard(
                systemImage: "hand.point.up.left.fill",
                title: "Try it now",
                detail: "Move the pointer to the top centre of your screen, or let Bondex open it for you.",
                action: "Show me"
            ) {
                environment.notch.panelTapped()
            }

            if choices.agents {
                readyCard(
                    systemImage: "terminal.fill",
                    title: "Using Claude Code or Codex?",
                    detail: """
                    Add Bondex's hook so the notch shows what each agent is doing — \
                    and turns amber when one needs you.
                    """,
                    action: "Set up agent hooks"
                ) {
                    environment.requestSettingsPage?(.widgets)
                }
            }

            if !choices.permissionsToRequest.isEmpty || choices.media || choices.downloads {
                Label {
                    Text("""
                    macOS may now ask for the access you chose. You can review it any \
                    time in Settings › Permissions.
                    """)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    private func readyCard(
        systemImage: String,
        title: String,
        detail: String,
        action: String,
        perform: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action, action: perform)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
        )
    }
}

// MARK: - Pieces

private struct OnboardingRow<Accessory: View>: View {
    let systemImage: String
    let accent: Color
    let title: String
    let detail: String
    @ViewBuilder var accessory: () -> Accessory

    init(
        systemImage: String,
        accent: Color,
        title: String,
        detail: String,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.accent = accent
        self.title = title
        self.detail = detail
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                    accessory()
                }
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A shortcut as keycaps: "⌃⌥ Space" becomes ⌃ ⌥ Space.
private struct KeyCaps: View {
    let shortcut: String

    private var keys: [String] {
        let parts = shortcut.split(separator: " ", maxSplits: 1).map(String.init)
        guard let modifiers = parts.first else { return [shortcut] }
        return modifiers.map(String.init) + parts.dropFirst()
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, key.count > 1 ? 7 : 5)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.09))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
                    )
            }
        }
        .accessibilityLabel(shortcut)
    }
}

private struct FeatureChoiceRow: View {
    let feature: OnboardingFeature
    let accent: Color
    @Binding var isOn: Bool
    let isAvailable: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: feature.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(feature.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Image(systemName: feature.asks == nil ? "checkmark.circle.fill" : "lock.fill")
                        .font(.system(size: 8.5, weight: .bold))
                    Text(feature.asks ?? "No permission needed")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(
                    feature.asks == nil
                        ? Color(red: 0.32, green: 0.80, blue: 0.55)
                        : Theme.attention.opacity(0.9)
                )
                .padding(.top, 1)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!isAvailable)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isOn && isAvailable ? 0.055 : 0.03))
        )
        .opacity(isAvailable ? 1 : 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A screen's top edge with the notch opened out of it, so "the notch" has a
/// picture before anyone has to find it.
private struct NotchIllustration: View {
    let accent: Color

    var body: some View {
        ZStack(alignment: .top) {
            // The display.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.17), Color(white: 0.11)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
                )

            // The menu bar.
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 14)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))

            // The panel, opened out of the notch.
            NotchShape(flareRadius: 6, bottomRadius: 12)
                .fill(Color.black)
                .frame(width: 196, height: 70)
                .overlay(alignment: .top) {
                    VStack(spacing: 7) {
                        HStack(spacing: 4) {
                            Capsule().fill(accent.opacity(0.5)).frame(width: 28, height: 7)
                            ForEach(0..<4, id: \.self) { _ in
                                Circle().fill(Color.white.opacity(0.2)).frame(width: 7, height: 7)
                            }
                        }
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 150, height: 20)
                            .overlay(alignment: .leading) {
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.7))
                                        .frame(width: 13, height: 13)
                                    Capsule().fill(Color.white.opacity(0.35)).frame(width: 60, height: 4)
                                }
                                .padding(.leading, 4)
                            }
                    }
                    .padding(.top, 20)
                }

            // The pointer that opened it.
            Image(systemName: "cursorarrow")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .offset(x: 40, y: 6)
        }
        .frame(width: 340, height: 104)
        .accessibilityHidden(true)
    }
}
