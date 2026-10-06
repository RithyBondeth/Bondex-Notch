import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case widgets
    case profiles
    case shortcuts
    case appearance
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .widgets: return "Widgets"
        case .profiles: return "Profiles"
        case .shortcuts: return "Shortcuts"
        case .appearance: return "Appearance"
        case .permissions: return "Permissions"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Interaction, keyboard, and accessibility"
        case .widgets: return "Choose what appears in your notch"
        case .profiles: return "Adapt widgets and appearance to your context"
        case .shortcuts: return "Build your personal quick-action grid"
        case .appearance: return "Shape, colour, material, and motion"
        case .permissions: return "Review access used by integrations"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .widgets: return "square.grid.2x2.fill"
        case .profiles: return "person.crop.circle.badge.clock.fill"
        case .shortcuts: return "bolt.square.fill"
        case .appearance: return "paintbrush.pointed.fill"
        case .permissions: return "lock.shield.fill"
        }
    }
}

struct SettingsView: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var settings: SettingsStore
    @State private var selection: SettingsPage

    init(environment: AppEnvironment, initialPage: SettingsPage = .general) {
        self.environment = environment
        self.settings = environment.settings
        self._selection = State(initialValue: initialPage)
    }

    var body: some View {
        ZStack {
            SettingsGlassBackdrop(accent: settings.effectiveAccentColor)

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 190)

                Rectangle()
                    .fill(Color.white.opacity(0.09))
                    .frame(width: 0.7)

                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                    pageContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .tint(settings.effectiveAccentColor)
        .frame(minWidth: 720, idealWidth: 800, minHeight: 520, idealHeight: 570)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BondexLogoMark()
                .frame(width: 36, height: 36)
                .shadow(color: settings.effectiveAccentColor.opacity(0.28), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Bondex Notch")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Settings")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 17)
            .padding(.bottom, 18)

            VStack(spacing: 5) {
                ForEach(SettingsPage.allCases) { page in
                    SettingsSidebarButton(
                        page: page,
                        isSelected: selection == page,
                        accent: settings.effectiveAccentColor
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) { selection = page }
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            HStack(spacing: 7) {
                Text("Free and open source")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text(Bundle.main.shortVersion)
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.045)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 36)
            .allowsHitTesting(false)
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selection.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(selection.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: selection.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(settings.effectiveAccentColor)
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: RoundedRectangle(
                    cornerRadius: 12, style: .continuous
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(settings.effectiveAccentColor.opacity(0.2), lineWidth: 0.8)
                )
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 13)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selection {
        case .general:
            GeneralSettings(settings: settings)
        case .widgets:
            WidgetSettings(environment: environment, settings: settings)
        case .profiles:
            ProfileSettings(environment: environment)
        case .shortcuts:
            ShortcutSettings(settings: settings)
        case .appearance:
            AppearanceSettings(settings: settings)
        case .permissions:
            PermissionsSettings(environment: environment)
        }
    }
}

private struct SettingsSidebarButton: View {
    let page: SettingsPage
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : Color.secondary)
                    .frame(width: 18)
                Text(page.title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(.thinMaterial)
                            : AnyShapeStyle(Color.white.opacity(hovering ? 0.055 : 0))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? accent.opacity(0.2) : Color.clear,
                        lineWidth: 0.75
                    )
            }
            .shadow(color: isSelected ? accent.opacity(0.08) : .clear, radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SettingsGlassBackdrop: View {
    let accent: Color

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.06, blue: 0.075)
            RadialGradient(
                colors: [accent.opacity(0.13), accent.opacity(0.035), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 430
            )
            RadialGradient(
                colors: [Color.blue.opacity(0.055), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 360
            )
            Rectangle().fill(.ultraThinMaterial).opacity(0.48)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

extension View {
    func modernSettingsForm() -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .controlSize(.regular)
    }
}

private extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: binding(\.launchAtLogin))
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Interaction") {
                Toggle("Expand when the pointer reaches the notch", isOn: binding(\.expandOnHover))
                Toggle("Show a compact peek while media is playing", isOn: binding(\.peekWhilePlaying))

                HStack {
                    Text("Hover delay")
                    Slider(value: binding(\.hoverDelay), in: 0...0.6, step: 0.02)
                    Text(String(format: "%.2fs", settings.preferences.hoverDelay))
                        .font(.caption.monospacedDigit())
                        .frame(width: 46, alignment: .trailing)
                }
                .disabled(!settings.preferences.expandOnHover)
                Text("""
                How long the pointer has to rest on the notch before it opens. \
                Raise this if the panel opens while you are on your way to the menu bar.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Text("Close delay")
                    Slider(value: binding(\.closeDelay), in: 0...1.5, step: 0.05)
                    Text(String(format: "%.2fs", settings.preferences.closeDelay))
                        .font(.caption.monospacedDigit())
                        .frame(width: 46, alignment: .trailing)
                }
                Text("How long the panel waits after the pointer leaves before closing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show synthetic notch on external displays", isOn: binding(\.showNotchOnExternalDisplays))
                Text("When turned off, the notch only appears on your Mac's built-in display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Feedback & support") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Send feedback or report an issue")
                            .font(.system(size: 13, weight: .medium))
                        Text("Email system diagnostics directly to the Bondex developer team.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Send Feedback…") {
                        sendFeedback()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Keyboard & accessibility") {
                Toggle("Global keyboard shortcut", isOn: binding(\.globalHotKeyEnabled))
                Picker("Shortcut", selection: binding(\.globalShortcut)) {
                    ForEach(GlobalShortcut.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }
                .disabled(!settings.preferences.globalHotKeyEnabled)

                Toggle("Quick Capture shortcut", isOn: binding(\.quickCaptureHotKeyEnabled))
                    .disabled(!settings.preferences.quickCaptureEnabled)
                Picker("Quick Capture", selection: binding(\.quickCaptureShortcut)) {
                    ForEach(QuickCaptureShortcut.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }
                .disabled(
                    !settings.preferences.quickCaptureEnabled
                        || !settings.preferences.quickCaptureHotKeyEnabled
                )

                Toggle("Command Palette shortcut", isOn: binding(\.commandPaletteHotKeyEnabled))
                Picker("Command Palette", selection: binding(\.commandPaletteShortcut)) {
                    ForEach(CommandPaletteShortcut.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }
                .disabled(!settings.preferences.commandPaletteHotKeyEnabled)

                Toggle(
                    "Announce important updates with VoiceOver",
                    isOn: binding(\.announceImportantUpdates)
                )

                HStack {
                    Text("Hardware HUD duration")
                    Slider(value: binding(\.systemHUDDuration), in: 0.8...5, step: 0.1)
                    Text(String(format: "%.1fs", settings.preferences.systemHUDDuration))
                        .font(.caption.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }

                Text("""
                Escape closes the panel; Left and Right Arrow switch tabs. In the Command Palette, \
                use Up and Down Arrow to navigate and Return to run a command.
                """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .modernSettingsForm()
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { settings.preferences[keyPath: keyPath] },
            set: { settings.preferences[keyPath: keyPath] = $0 }
        )
    }

    private func sendFeedback() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let hasNotch = (NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) != nil) ? "Yes" : "No"
        let subject = "Bondex Notch Feedback (v\(version))".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = """
        [Describe your feedback, feature request, or issue here]

        ---
        App Version: \(version)
        macOS: \(osVersion)
        Hardware Notch: \(hasNotch)
        """.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:support@bondeth.site?subject=\(subject)&body=\(body)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Widgets

private struct WidgetSettings: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var settings: SettingsStore
    /// Observed directly so the browser hint appears the moment a poll finds a
    /// browser with JavaScript still switched off.
    @ObservedObject private var nowPlaying: NowPlayingService

    init(environment: AppEnvironment, settings: SettingsStore) {
        self.environment = environment
        self.settings = settings
        self.nowPlaying = environment.nowPlaying
    }

    var body: some View {
        Form {
            if let profile = settings.activeProfile {
                // While a profile is active its own widget list and tab order
                // decide what the notch shows. Without saying so, the toggles
                // and arrows below appeared to do nothing at all.
                Section {
                    Label {
                        Text("""
                        The \(profile.displayName) profile is active, so its own widget \
                        list and tab order are in use. Changes here apply when no profile \
                        is active; edit the profile under Profiles.
                        """)
                        .font(.caption)
                    } icon: {
                        Image(systemName: profile.systemImage)
                            .foregroundStyle(settings.effectiveAccentColor)
                    }
                }
            }

            Section("Widgets") {
                Toggle("Music", isOn: binding(\.musicWidgetEnabled))
                Toggle("Agent activity", isOn: binding(\.agentActivityEnabled))
                Toggle("Agent usage dashboard", isOn: binding(\.agentUsageEnabled))
                Toggle("System", isOn: binding(\.systemWidgetEnabled))
                Toggle("Show hardware controls in notch", isOn: binding(\.systemHUDEnabled))
                Toggle("Microphone and camera privacy indicator", isOn: binding(\.privacyIndicatorsEnabled))
                Toggle("Show system summary on Home", isOn: binding(\.showSystemSummaryOnHome))
                    .disabled(!settings.preferences.systemWidgetEnabled)
                Toggle("Custom live activities", isOn: binding(\.customLiveActivitiesEnabled))
                Toggle("Focus timer", isOn: binding(\.focusTimerEnabled))
                Stepper(
                    "Default focus: \(settings.preferences.defaultFocusMinutes) minutes",
                    value: binding(\.defaultFocusMinutes),
                    in: 5...90,
                    step: 5
                )
                .disabled(!settings.preferences.focusTimerEnabled)

                Toggle("Upcoming meetings", isOn: meetingsBinding)
                Toggle(
                    "Show meeting titles in compact notch",
                    isOn: binding(\.showMeetingTitlesInPeek)
                )
                .disabled(!settings.preferences.upcomingMeetingsEnabled)
                Toggle("Activity feed", isOn: binding(\.activityFeedEnabled))
                Toggle("Clipboard history", isOn: binding(\.clipboardHistoryEnabled))
                Toggle("Quick Capture", isOn: binding(\.quickCaptureEnabled))
                Toggle(
                    "Enhance captures with Apple Intelligence",
                    isOn: binding(\.appleIntelligenceCaptureEnabled)
                )
                .disabled(!settings.preferences.quickCaptureEnabled)
                Text("Enhancement is always user-triggered and uses Apple's on-device model when available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .disabled(!settings.preferences.quickCaptureEnabled)
                Toggle("Custom shortcuts", isOn: binding(\.customShortcutsEnabled))
            }

            Section("Files") {
                Toggle("File activity", isOn: binding(\.fileActivityEnabled))
                Toggle("Drop shelf", isOn: binding(\.shelfEnabled))
            }

            Section("Tab order") {
                ForEach(settings.standardOrderedTabs) { tab in
                    HStack {
                        Label(tab.title, symbol: tab.systemImage)
                        Spacer()
                        Button {
                            move(tab, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(settings.standardOrderedTabs.first == tab)
                        .help("Move " + tab.title + " left")

                        Button {
                            move(tab, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(settings.standardOrderedTabs.last == tab)
                        .help("Move " + tab.title + " right")
                    }
                }
            }

            Section {
                Text("Clipboard items stay in memory for this session and are never written to disk. Entries marked concealed or transient by password managers are ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Clipboard Privacy")
            }

            Section {
                Text("Uses device running-state APIs without opening or recording either device. macOS does not provide a public API that identifies which app is using it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy Indicator")
            }

            Section {
                Text(liveCommands)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button("Copy example commands") { copyLiveCommands() }
            } header: {
                Text("Custom Live Activities")
            } footer: {
                Text("Use these from scripts, Shortcuts, build tools, or any terminal.")
                    .font(.caption)
            }

            Section {
                AgentSetupHelp(environment: environment)
            } header: {
                Text("Agent Activity")
            } footer: {
                Text("""
                Shows a mark beside the notch while Claude Code or Codex is \
                working, with what it is doing and how long it has been at it.
                """)
                .font(.caption)
            }

            Section {
                Text("""
                Tokens, spend, projects and models come from Claude Code's and \
                Codex's own session logs. Codex records its plan and limits in \
                the same logs; Claude's limits come from the Claude desktop app, \
                which keeps them while it runs, and its plan from the account \
                profile Claude Code caches. Spend is what the tokens would cost \
                at public API prices.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Agent Usage")
            } footer: {
                Text("Read-only and on this Mac. Bondex signs in to nothing and sends nothing.")
                    .font(.caption)
            }

            Section {
                Toggle("Include browser tabs", isOn: binding(\.browserMediaEnabled))
                    .disabled(!settings.preferences.musicWidgetEnabled)

                if let browser = nowPlaying.blockedBrowser {
                    Text(browser.javaScriptHint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    BrowserFixButton(nowPlaying: nowPlaying, browser: browser)
                }
            } header: {
                Text("Media")
            } footer: {
                Text("""
                Music and Spotify report what they are playing directly. Browsers \
                do not, so Bondex asks the tab that owns the audio — which is what \
                makes YouTube, YouTube Music, SoundCloud and the rest show up. Each \
                browser needs "Allow JavaScript from Apple Events" turned on once.
                """)
                .font(.caption)
            }

            Section {
                LabeledContent("Watching") {
                    Text(downloadsPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("File Activity")
            } footer: {
                Text("Bondex reports transfers landing in your Downloads folder.")
                    .font(.caption)
            }
        }
        .modernSettingsForm()
    }

    private var downloadsPath: String {
        FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask)
            .first?.path(percentEncoded: false) ?? "—"
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { settings.preferences[keyPath: keyPath] },
            set: { settings.preferences[keyPath: keyPath] = $0 }
        )
    }

    private var meetingsBinding: Binding<Bool> {
        Binding(
            get: { settings.preferences.upcomingMeetingsEnabled },
            set: { enabled in
                settings.preferences.upcomingMeetingsEnabled = enabled
                if enabled, environment.meetings.authorizationStatus != .fullAccess {
                    environment.meetings.requestAuthorization()
                }
            }
        )
    }

    private func move(_ tab: NotchTab, by offset: Int) {
        // The standard order, not `orderedTabs`: with a profile active that is
        // the profile's own subset, and writing it here scrambled the global
        // layout the user returns to when the profile ends.
        var order = settings.standardOrderedTabs
        guard let source = order.firstIndex(of: tab) else { return }
        let destination = source + offset
        guard order.indices.contains(destination) else { return }
        order.swapAt(source, destination)
        settings.preferences.widgetOrder = order
    }

    private var liveCommands: String {
        let binary = Bundle.main.executableURL?.path ?? "BondexNotch"
        return """
        "\(binary)" --live-start build --title "Building release" --progress 0.2
        "\(binary)" --live-update build --subtitle "Running tests" --progress 0.75
        "\(binary)" --live-finish build --message "Build succeeded"
        """
    }

    private func copyLiveCommands() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(liveCommands, forType: .string)
    }
}

// MARK: - Custom shortcuts

private struct ShortcutSettings: View {
    @ObservedObject var settings: SettingsStore

    @State private var shortcutName = ""
    @State private var selectedWidget: NotchTab = .system

    private var actions: [CustomAction] { settings.preferences.customActions }
    private var canAdd: Bool { actions.count < 8 }
    private var toggleableTabs: [NotchTab] {
        NotchTab.allCases.filter { $0 != .home && $0 != .shortcuts }
    }

    var body: some View {
        Form {
            Section {
                if actions.isEmpty {
                    Text("No actions yet. Add an application, Apple Shortcut, or widget toggle below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        actionRow(action, at: index)
                    }
                }
            } header: {
                Text("Quick actions")
            } footer: {
                Text("Up to eight actions appear as compact tiles in the Shortcuts tab.")
                    .font(.caption)
            }

            Section("Open an application") {
                Button("Choose Application…") { chooseApplication() }
                    .disabled(!canAdd)
                Text("The app is resolved by bundle identifier first, so moving it does not break the action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Run an Apple Shortcut") {
                TextField("Exact Shortcut name", text: $shortcutName)
                Button("Add Apple Shortcut") { addAppleShortcut() }
                    .disabled(
                        !canAdd
                            || shortcutName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                Text("Runs with the macOS shortcuts command using the saved name as a single argument.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Toggle a widget") {
                Picker("Widget", selection: $selectedWidget) {
                    ForEach(toggleableTabs) { tab in
                        Label(tab.title, symbol: tab.systemImage).tag(tab)
                    }
                }
                Button("Add Widget Toggle") { addWidgetToggle() }
                    .disabled(!canAdd)
            }
        }
        .modernSettingsForm()
    }

    private func actionRow(_ action: CustomAction, at index: Int) -> some View {
        HStack(spacing: 9) {
            SymbolIcon(name: action.systemImage, size: 12, weight: .semibold)
                .foregroundStyle(settings.effectiveAccentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Action name", text: titleBinding(for: action.id))
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                Text(action.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                moveAction(at: index, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("Move up")

            Button {
                moveAction(at: index, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == actions.count - 1)
            .help("Move down")

            Button(role: .destructive) {
                removeAction(action.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove action")
        }
    }

    private func titleBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { actions.first(where: { $0.id == id })?.title ?? "" },
            set: { value in
                var next = actions
                guard let index = next.firstIndex(where: { $0.id == id }) else { return }
                next[index].title = String(value.prefix(40))
                settings.preferences.customActions = next
            }
        )
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.prompt = "Add Action"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let bundle = Bundle(url: url)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        add(CustomAction(
            title: name,
            target: .application(
                bundleIdentifier: bundle?.bundleIdentifier,
                path: url.path
            )
        ))
    }

    private func addAppleShortcut() {
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        add(CustomAction(title: name, target: .appleShortcut(name: name)))
        shortcutName = ""
    }

    private func addWidgetToggle() {
        add(CustomAction(
            title: selectedWidget.title,
            target: .toggleWidget(selectedWidget)
        ))
    }

    private func add(_ action: CustomAction) {
        guard canAdd, !actions.contains(where: { $0.target == action.target }) else { return }
        settings.preferences.customActions.append(action)
    }

    private func removeAction(_ id: UUID) {
        settings.preferences.customActions.removeAll { $0.id == id }
    }

    private func moveAction(at index: Int, by offset: Int) {
        let destination = index + offset
        guard actions.indices.contains(index), actions.indices.contains(destination) else { return }
        var next = actions
        next.swapAt(index, destination)
        settings.preferences.customActions = next
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Accent") {
                Picker("Accent", selection: Binding(
                    get: { settings.preferences.accent },
                    set: { settings.preferences.accent = $0 }
                )) {
                    ForEach(Theme.Accent.allCases) { accent in
                        HStack {
                            Circle()
                                .fill(accent == .custom ? settings.effectiveAccentColor : accent.color)
                                .frame(width: 10, height: 10)
                            Text(accent.displayName)
                        }
                        .tag(accent)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                ColorPicker("Custom color", selection: customAccent, supportsOpacity: false)
            }


            Section("Panel") {
                Picker("Background", selection: binding(\.panelStyle)) {
                    ForEach(Theme.PanelStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                valueSlider(
                    "Width",
                    value: binding(\.panelWidth),
                    range: 440...680,
                    step: 10,
                    valueLabel: "\(Int(settings.preferences.panelWidth)) pt"
                )
                valueSlider(
                    "Opacity",
                    value: binding(\.panelOpacity),
                    range: 0.65...1,
                    step: 0.05,
                    valueLabel: "\(Int(settings.preferences.panelOpacity * 100))%"
                )
                valueSlider(
                    "Bottom corners",
                    value: binding(\.bottomCornerRadius),
                    range: 10...38,
                    step: 1,
                    valueLabel: "\(Int(settings.preferences.bottomCornerRadius)) pt"
                )
                valueSlider(
                    "Top flare",
                    value: binding(\.flareRadius),
                    range: 5...20,
                    step: 1,
                    valueLabel: "\(Int(settings.preferences.flareRadius)) pt"
                )
                valueSlider(
                    "Rim",
                    value: binding(\.rimStrength),
                    range: 0...1,
                    step: 0.1,
                    valueLabel: "\(Int(settings.preferences.rimStrength * 100))%"
                )
                valueSlider(
                    "Shadow",
                    value: binding(\.shadowStrength),
                    range: 0...1,
                    step: 0.1,
                    valueLabel: "\(Int(settings.preferences.shadowStrength * 100))%"
                )
            }

            Section("Motion") {
                Picker("Animation speed", selection: Binding(
                    get: { settings.preferences.motionSpeed },
                    set: { settings.preferences.motionSpeed = $0 }
                )) {
                    ForEach(Motion.Speed.allCases) { speed in
                        Text(speed.displayName).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("Reset appearance") { settings.resetAppearance() }
            }
        }
        .modernSettingsForm()
    }

    private var customAccent: Binding<Color> {
        Binding(
            get: { Color(hexRGB: settings.preferences.customAccentHex) ?? .white },
            set: {
                if let hex = $0.hexRGB { settings.preferences.customAccentHex = hex }
                settings.preferences.accent = .custom
            }
        )
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { settings.preferences[keyPath: keyPath] },
            set: { settings.preferences[keyPath: keyPath] = $0 }
        )
    }

    private func valueSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueLabel: String
    ) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range, step: step)
            Text(valueLabel)
                .font(.caption.monospacedDigit())
                .frame(width: 54, alignment: .trailing)
        }
    }
}

// MARK: - Permissions

/// The blocked browser's fix, as a native button for the Settings window.
private struct BrowserFixButton: View {
    @ObservedObject var nowPlaying: NowPlayingService
    let browser: MediaApp

    @State private var isConfirming = false
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            switch browser.mediaAccessFix {
            case .relaunch:
                Button(isWorking ? "Reopening \(browser.displayName)…" : "Reopen \(browser.displayName)") {
                    isConfirming = true
                }
                .disabled(isWorking)
                .confirmationDialog(
                    "Reopen \(browser.displayName)?",
                    isPresented: $isConfirming
                ) {
                    Button("Reopen") { reopen() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("\(browser.displayName) will quit and open again so it can share what’s playing. It normally brings your tabs back.")
                }
            case .browserSetting:
                Button("Open \(browser.displayName)") { BrowserMediaSetup.bringToFront(browser) }
            case nil:
                EmptyView()
            }
            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func reopen() {
        isWorking = true
        failure = nil
        Task {
            let outcome = await nowPlaying.fixBlockedBrowser()
            isWorking = false
            switch outcome {
            case .done: break
            case .didNotQuit: failure = "\(browser.displayName) didn’t quit — it may be asking about open tabs."
            case .couldNotOpen: failure = "Couldn’t reopen \(browser.displayName)."
            }
        }
    }
}

private struct PermissionsSettings: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var nowPlaying: NowPlayingService
    @ObservedObject private var meetings: UpcomingMeetingService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.nowPlaying = environment.nowPlaying
        self.meetings = environment.meetings
    }

    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "Automation",
                    detail: "Lets Bondex read and control Music, Spotify and your browser.",
                    isGranted: !nowPlaying.automationDenied,
                    settingsPane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                )

                if let browser = nowPlaying.blockedBrowser {
                    // Not a TCC permission, so there is no pane to open — it is a
                    // switch inside the browser itself.
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("JavaScript from Apple Events").fontWeight(.medium)
                            Text(browser.javaScriptHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        BrowserFixButton(nowPlaying: nowPlaying, browser: browser)
                    }
                    .padding(.vertical, 3)
                }

                permissionRow(
                    title: "Files and Folders",
                    detail: "Lets Bondex watch your Downloads folder.",
                    isGranted: !environment.files.accessDenied,
                    settingsPane: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
                )

                permissionRow(
                    title: "Notifications",
                    detail: "Lets Bondex post its own alerts to Notification Center.",
                    isGranted: environment.notifications.authorizationStatus == .authorized,
                    settingsPane: "x-apple.systempreferences:com.apple.preference.notifications",
                    action: environment.notifications.requestAuthorization
                )

                permissionRow(
                    title: "Calendar",
                    detail: "Lets Bondex show your next meeting and its join link.",
                    isGranted: meetings.authorizationStatus == .fullAccess,
                    settingsPane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
                    action: meetings.requestAuthorization
                )
            } footer: {
                Text("""
                macOS provides no public way to read other apps' notifications or \
                system-wide Now Playing data, so the Activity feed reports what \
                Bondex observes directly, and media is read from the players and \
                browser tabs themselves.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .modernSettingsForm()
    }

    private func permissionRow(
        title: String,
        detail: String,
        isGranted: Bool,
        settingsPane: String,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if let action, !isGranted {
                Button("Request") { action() }
            } else {
                Button("Open") {
                    if let url = URL(string: settingsPane) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}
