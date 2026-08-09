import EventKit
import SwiftUI

struct ProfileSettings: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var smartProfiles: SmartProfileService

    @State private var editingProfileID: UUID?

    private static let symbols = [
        "briefcase.fill", "video.fill", "play.circle.fill", "gamecontroller.fill",
        "airplane", "house.fill", "graduationcap.fill", "figure.run", "sparkles"
    ]

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settings = environment.settings
        self.smartProfiles = environment.smartProfiles
        self._editingProfileID = State(
            initialValue: environment.settings.preferences.selectedProfileID
                ?? environment.settings.preferences.notchProfiles.first?.id
        )
    }

    var body: some View {
        Form {
            modeSection
            profilePickerSection

            if let profile = editingProfile {
                identitySection(profile)
                widgetsSection(profile)
                rulesSection(profile)
            }
        }
        .modernSettingsForm()
        .onChange(of: settings.preferences.notchProfiles.map(\.id)) { _, ids in
            if let editingProfileID, ids.contains(editingProfileID) { return }
            self.editingProfileID = ids.first
        }
    }

    private var modeSection: some View {
        Section("Smart switching") {
            Picker("Mode", selection: binding(\.smartProfileMode)) {
                ForEach(SmartProfileMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if settings.preferences.smartProfileMode == .manual {
                Picker("Active profile", selection: selectedProfileBinding) {
                    ForEach(settings.preferences.notchProfiles) { profile in
                        Label(profile.displayName, systemImage: profile.systemImage).tag(profile.id)
                    }
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(settings.activeProfile == nil ? Color.secondary : Color.green)
                    .frame(width: 7, height: 7)
                Text(settings.activeProfile.map { "\($0.displayName) is active" } ?? "Standard setup is active")
                    .font(.caption.weight(.semibold))
                Spacer()
                if settings.preferences.smartProfileMode == .automatic {
                    Text("First matching profile wins")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Automatic matching stays on device and checks only the frontmost app, hour, power source, display count, and whether a meeting is starting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var profilePickerSection: some View {
        Section("Profiles") {
            HStack(spacing: 8) {
                Picker("Edit", selection: editingProfileBinding) {
                    ForEach(settings.preferences.notchProfiles) { profile in
                        Label(profile.displayName, systemImage: profile.systemImage).tag(profile.id)
                    }
                }

                Button { addProfile() } label: {
                    Image(systemName: "plus")
                }
                .help("Add profile")

                Button { duplicateProfile() } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .disabled(editingProfile == nil)
                .help("Duplicate profile")

                Button { moveProfile(by: -1) } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(profileIndex == nil || profileIndex == 0)
                .help("Raise automatic priority")

                Button { moveProfile(by: 1) } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(
                    profileIndex == nil
                        || profileIndex == settings.preferences.notchProfiles.count - 1
                )
                .help("Lower automatic priority")

                Button(role: .destructive) { deleteProfile() } label: {
                    Image(systemName: "trash")
                }
                .disabled(settings.preferences.notchProfiles.count <= 1 || editingProfile == nil)
                .help("Delete profile")
            }
        }
    }

    private func identitySection(_ profile: NotchProfile) -> some View {
        Section("Profile appearance") {
            TextField("Name", text: profileBinding(\.name, fallback: profile.name))

            Picker("Symbol", selection: profileBinding(\.systemImage, fallback: profile.systemImage)) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Label(symbol.replacingOccurrences(of: ".fill", with: "").capitalized, systemImage: symbol)
                        .tag(symbol)
                }
            }

            Picker("Accent", selection: profileBinding(\.accent, fallback: profile.accent)) {
                ForEach(Theme.Accent.allCases.filter { $0 != .custom }) { accent in
                    Text(accent.displayName).tag(accent)
                }
            }

            Picker("Background", selection: profileBinding(\.panelStyle, fallback: profile.panelStyle)) {
                ForEach(Theme.PanelStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }

            HStack {
                Text("Width")
                Slider(
                    value: profileBinding(\.panelWidth, fallback: profile.panelWidth),
                    in: 440...680,
                    step: 10
                )
                Text("\(Int(profile.panelWidth)) pt")
                    .font(.caption.monospacedDigit())
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private func widgetsSection(_ profile: NotchProfile) -> some View {
        Section("Widgets and order") {
            ForEach(profile.orderedTabs) { tab in
                HStack {
                    Toggle(isOn: tabEnabledBinding(tab, profileID: profile.id)) {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .disabled(tab == .home)

                    Spacer()
                    Button {
                        move(tab, by: -1, profileID: profile.id)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(profile.orderedTabs.first == tab)

                    Button {
                        move(tab, by: 1, profileID: profile.id)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(profile.orderedTabs.last == tab)
                }
            }

            Menu("Add hidden widget") {
                ForEach(NotchTab.allCases.filter { !profile.enabledTabs.contains($0) && $0 != .home }) { tab in
                    Button {
                        setTab(tab, enabled: true, profileID: profile.id)
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                }
            }
            .disabled(NotchTab.allCases.allSatisfy { profile.enabledTabs.contains($0) })
        }
    }

    private func rulesSection(_ profile: NotchProfile) -> some View {
        Section("Automatic rules") {
            ForEach(profile.rules.applicationBundleIdentifiers.indices, id: \.self) { index in
                HStack {
                    TextField(
                        "Bundle identifier",
                        text: applicationRuleBinding(profile.id, index: index)
                    )
                    Button(role: .destructive) {
                        removeApplicationRule(profile.id, index: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove application rule")
                }
            }

            Button("Add application rule", systemImage: "plus") {
                updateProfile(profile.id) { $0.rules.applicationBundleIdentifiers.append("") }
            }

            Text("Use bundle identifiers such as com.apple.dt.Xcode. Every enabled condition must match; profiles are checked from top to bottom.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Only during these hours", isOn: ruleBinding(\.timeRangeEnabled, profile: profile))
            if profile.rules.timeRangeEnabled {
                HStack {
                    Picker("From", selection: ruleBinding(\.startHour, profile: profile)) {
                        ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                    }
                    Picker("Until", selection: ruleBinding(\.endHour, profile: profile)) {
                        ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                    }
                }
            }

            Picker("Power", selection: ruleBinding(\.power, profile: profile)) {
                ForEach(ProfilePowerCondition.allCases) { condition in
                    Text(condition.title).tag(condition)
                }
            }

            Picker("Displays", selection: ruleBinding(\.displays, profile: profile)) {
                ForEach(ProfileDisplayCondition.allCases) { condition in
                    Text(condition.title).tag(condition)
                }
            }

            Toggle("While a meeting is starting", isOn: meetingRuleBinding(profile))

            if !profile.rules.hasConditions {
                Text("This profile is manual until at least one automatic rule is added.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var editingProfile: NotchProfile? {
        settings.preferences.notchProfiles.first { $0.id == editingProfileID }
    }

    private var profileIndex: Int? {
        settings.preferences.notchProfiles.firstIndex { $0.id == editingProfileID }
    }

    private var editingProfileBinding: Binding<UUID> {
        Binding(
            get: { editingProfileID ?? settings.preferences.notchProfiles.first?.id ?? UUID() },
            set: { editingProfileID = $0 }
        )
    }

    private var selectedProfileBinding: Binding<UUID> {
        Binding(
            get: {
                settings.preferences.selectedProfileID
                    ?? settings.preferences.notchProfiles.first?.id
                    ?? UUID()
            },
            set: { settings.preferences.selectedProfileID = $0 }
        )
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { settings.preferences[keyPath: keyPath] },
            set: { settings.preferences[keyPath: keyPath] = $0 }
        )
    }

    private func profileBinding<T>(
        _ keyPath: WritableKeyPath<NotchProfile, T>,
        fallback: T
    ) -> Binding<T> {
        Binding(
            get: { editingProfile?[keyPath: keyPath] ?? fallback },
            set: { value in updateProfile(editingProfileID) { $0[keyPath: keyPath] = value } }
        )
    }

    private func ruleBinding<T>(
        _ keyPath: WritableKeyPath<NotchProfileRules, T>,
        profile: NotchProfile
    ) -> Binding<T> {
        Binding(
            get: { editingProfile?.rules[keyPath: keyPath] ?? profile.rules[keyPath: keyPath] },
            set: { value in updateProfile(profile.id) { $0.rules[keyPath: keyPath] = value } }
        )
    }

    private func applicationRuleBinding(_ profileID: UUID, index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let profile = settings.preferences.notchProfiles.first(where: {
                    $0.id == profileID
                }), profile.rules.applicationBundleIdentifiers.indices.contains(index) else {
                    return ""
                }
                return profile.rules.applicationBundleIdentifiers[index]
            },
            set: { value in
                updateProfile(profileID) { profile in
                    guard profile.rules.applicationBundleIdentifiers.indices.contains(index) else {
                        return
                    }
                    profile.rules.applicationBundleIdentifiers[index] = value
                }
            }
        )
    }

    private func removeApplicationRule(_ profileID: UUID, index: Int) {
        updateProfile(profileID) { profile in
            guard profile.rules.applicationBundleIdentifiers.indices.contains(index) else { return }
            profile.rules.applicationBundleIdentifiers.remove(at: index)
        }
    }

    private func meetingRuleBinding(_ profile: NotchProfile) -> Binding<Bool> {
        Binding(
            get: { editingProfile?.rules.duringMeeting ?? profile.rules.duringMeeting },
            set: { enabled in
                updateProfile(profile.id) { $0.rules.duringMeeting = enabled }
                if enabled, environment.meetings.authorizationStatus != .fullAccess {
                    environment.meetings.requestAuthorization()
                }
            }
        )
    }

    private func tabEnabledBinding(_ tab: NotchTab, profileID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                settings.preferences.notchProfiles.first { $0.id == profileID }?
                    .enabledTabs.contains(tab) ?? false
            },
            set: { setTab(tab, enabled: $0, profileID: profileID) }
        )
    }

    private func setTab(_ tab: NotchTab, enabled: Bool, profileID: UUID) {
        updateProfile(profileID) { profile in
            profile.enabledTabs.removeAll { $0 == tab }
            if enabled { profile.enabledTabs.append(tab) }
        }
    }

    private func move(_ tab: NotchTab, by offset: Int, profileID: UUID) {
        updateProfile(profileID) { profile in
            var order = profile.orderedTabs
            guard let source = order.firstIndex(of: tab) else { return }
            let destination = source + offset
            guard order.indices.contains(destination) else { return }
            order.swapAt(source, destination)
            profile.widgetOrder = order + NotchTab.allCases.filter { !order.contains($0) }
        }
    }

    private func updateProfile(_ id: UUID?, change: (inout NotchProfile) -> Void) {
        guard let id,
              let index = settings.preferences.notchProfiles.firstIndex(where: { $0.id == id })
        else { return }
        change(&settings.preferences.notchProfiles[index])
    }

    private func addProfile() {
        let profile = NotchProfile(name: "Custom Profile")
        settings.preferences.notchProfiles.append(profile)
        editingProfileID = profile.id
    }

    private func duplicateProfile() {
        guard var profile = editingProfile else { return }
        profile.id = UUID()
        profile.name += " Copy"
        settings.preferences.notchProfiles.append(profile)
        editingProfileID = profile.id
    }

    private func deleteProfile() {
        guard let id = editingProfileID, settings.preferences.notchProfiles.count > 1 else { return }
        settings.preferences.notchProfiles.removeAll { $0.id == id }
        let replacement = settings.preferences.notchProfiles.first?.id
        editingProfileID = replacement
        if settings.preferences.selectedProfileID == id {
            settings.preferences.selectedProfileID = replacement
        }
    }

    private func moveProfile(by offset: Int) {
        guard let source = profileIndex else { return }
        let destination = source + offset
        guard settings.preferences.notchProfiles.indices.contains(destination) else { return }
        settings.preferences.notchProfiles.swapAt(source, destination)
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour)) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
