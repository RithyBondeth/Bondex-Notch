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

    var body: some View {
        Form {
            Section("Free") {
                Toggle("Music", isOn: binding(\.musicWidgetEnabled))
                Toggle("System", isOn: binding(\.systemWidgetEnabled))
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
                            Circle().fill(accent.color).frame(width: 10, height: 10)
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
        }
        .formStyle(.grouped)
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

    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "Automation",
                    detail: "Lets Bondex read and control Music and Spotify.",
                    isGranted: !environment.nowPlaying.automationDenied,
                    settingsPane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                )

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
            } footer: {
                Text("""
                macOS provides no public way to read other apps' notifications or \
                system-wide Now Playing data, so the Activity feed reports what \
                Bondex observes directly and media comes from Music and Spotify.
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
