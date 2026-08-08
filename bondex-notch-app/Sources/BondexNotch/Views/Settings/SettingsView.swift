import AppKit
import SwiftUI

struct SettingsView: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var settings: SettingsStore

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settings = environment.settings
    }

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }

            WidgetSettings(environment: environment, settings: settings)
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2") }

            AppearanceSettings(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            LicenseSettings(settings: settings)
                .tabItem { Label("License", systemImage: "key") }

            PermissionsSettings(environment: environment)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 600, height: 470)
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
            }

            Section("Keyboard & accessibility") {
                Toggle("Global keyboard shortcut", isOn: binding(\.globalHotKeyEnabled))
                Picker("Shortcut", selection: binding(\.globalShortcut)) {
                    ForEach(GlobalShortcut.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }
                .disabled(!settings.preferences.globalHotKeyEnabled)

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

                Text("Escape closes the panel; Left and Right Arrow switch tabs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { settings.preferences[keyPath: keyPath] },
            set: { settings.preferences[keyPath: keyPath] = $0 }
        )
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
            Section("Free") {
                Toggle("Music", isOn: binding(\.musicWidgetEnabled))
                Toggle("Agent activity", isOn: binding(\.agentActivityEnabled))
                Toggle("System", isOn: binding(\.systemWidgetEnabled))
                Toggle("Show hardware controls in notch", isOn: binding(\.systemHUDEnabled))
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
            }

            Section("Pro") {
                Toggle("File activity", isOn: binding(\.fileActivityEnabled))
                    .disabled(!settings.isUnlocked(.fileActivity))
                Toggle("Drop shelf", isOn: binding(\.shelfEnabled))
                    .disabled(!settings.isUnlocked(.shelf))

                if settings.tier != .pro {
                    Text("Pro widgets stay visible but inactive until a license key is added.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tab order") {
                ForEach(settings.orderedTabs) { tab in
                    HStack {
                        Label(tab.title, systemImage: tab.systemImage)
                        Spacer()
                        Button {
                            move(tab, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(settings.orderedTabs.first == tab)
                        .help("Move " + tab.title + " left")

                        Button {
                            move(tab, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(settings.orderedTabs.last == tab)
                        .help("Move " + tab.title + " right")
                    }
                }
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
                Toggle("Include browser tabs", isOn: binding(\.browserMediaEnabled))
                    .disabled(!settings.preferences.musicWidgetEnabled)

                if let browser = nowPlaying.blockedBrowser {
                    Text(browser.javaScriptHint)
                        .font(.caption)
                        .foregroundStyle(.orange)
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
        .formStyle(.grouped)
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
        var order = settings.orderedTabs
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
                            if accent.requiresPro && settings.tier != .pro {
                                Text("Pro").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .tag(accent)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if settings.tier != .pro {
                    Text("Custom accents require Pro; Graphite is used until then.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }


                ColorPicker("Custom color", selection: customAccent, supportsOpacity: false)
                    .disabled(settings.tier != .pro)
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
        .formStyle(.grouped)
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

// MARK: - License

private struct LicenseSettings: View {
    @ObservedObject var settings: SettingsStore
    @State private var draftKey = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Current tier") {
                    Text(settings.tier.displayName)
                        .fontWeight(.semibold)
                        .foregroundStyle(settings.tier == .pro ? .green : .secondary)
                }
            }

            Section("License key") {
                TextField(LicenseValidator.keyFormat, text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())

                HStack {
                    Button("Apply") { apply() }
                        .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Remove") {
                        settings.preferences.licenseKey = ""
                        draftKey = ""
                        message = "License removed."
                    }
                    .disabled(settings.preferences.licenseKey.isEmpty)
                }

                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Pro includes") {
                ForEach(ProFeature.allCases) { feature in
                    Label(feature.displayName, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { draftKey = settings.preferences.licenseKey }
    }

    private func apply() {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if LicenseValidator.validate(key) {
            settings.preferences.licenseKey = key
            message = "Pro unlocked."
        } else {
            message = "That key is not valid."
        }
    }
}

// MARK: - Permissions

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
        .formStyle(.grouped)
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
