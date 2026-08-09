import AppKit
import Combine
import SwiftUI

/// Composition root. Owns every service and keeps them in step with settings.
@MainActor
final class AppEnvironment: ObservableObject {

    let settings: SettingsStore
    let events: EventCenter
    let nowPlaying: NowPlayingService
    let metrics: SystemMetricsService
    let systemHUD: SystemHUDService
    let deviceBatteries: DeviceBatteryService
    let privacyActivity: PrivacyActivityService
    let focusTimer: FocusTimerService
    let meetings: UpcomingMeetingService
    let smartProfiles: SmartProfileService
    let globalHotKey: GlobalHotKeyService
    let accessibilityAnnouncements: AccessibilityAnnouncementService
    let quickCapture: QuickCaptureService
    let captureIntelligence: CaptureIntelligenceService
    let commandPalette: CommandPaletteService
    let customActions: CustomActionService
    let files: FileActivityService
    let clipboard: ClipboardHistoryService
    let shelf: ShelfService
    let agents: AgentActivityService
    let liveActivities: LiveActivityService
    let notifications: NotificationService
    let notch: NotchViewModel

    /// Installed by the window controller so a global shortcut can make the
    /// nonactivating panel keyboard-operable without activating the whole app.
    var requestKeyboardFocus: (() -> Void)?
    var requestSettingsPage: ((SettingsPage) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    /// `defaults` is injectable so the offscreen preview tool can run against a
    /// throwaway domain instead of the user's real preferences.
    init(screen: NSScreen, defaults: UserDefaults = .standard) {
        let settings = SettingsStore(defaults: defaults)
        let events = EventCenter()

        self.settings = settings
        self.events = events
        self.nowPlaying = NowPlayingService(events: events)
        self.metrics = SystemMetricsService(events: events)
        self.systemHUD = SystemHUDService()
        self.deviceBatteries = DeviceBatteryService()
        self.privacyActivity = PrivacyActivityService()
        self.focusTimer = FocusTimerService(defaults: defaults, events: events)
        self.meetings = UpcomingMeetingService()
        self.smartProfiles = SmartProfileService(settings: settings)
        self.globalHotKey = GlobalHotKeyService()
        self.accessibilityAnnouncements = AccessibilityAnnouncementService()
        self.quickCapture = QuickCaptureService(defaults: defaults)
        self.captureIntelligence = CaptureIntelligenceService()
        self.commandPalette = CommandPaletteService()
        self.customActions = CustomActionService()
        self.files = FileActivityService(events: events)
        self.clipboard = ClipboardHistoryService()
        self.shelf = ShelfService(events: events)
        self.agents = AgentActivityService(events: events)
        self.liveActivities = LiveActivityService(events: events)
        self.notifications = NotificationService(events: events)
        self.notch = NotchViewModel(settings: settings, events: events, screen: screen)

        wire()
    }

    private func wire() {
        globalHotKey.onPress = { [weak self] in
            guard let self else { return }
            guard self.settings.canUseApp else {
                self.notch.setPinned(true)
                self.notch.expand()
                return
            }
            let isOpening = !self.notch.state.isExpanded
            if !isOpening { self.commandPalette.dismiss() }
            self.notch.toggle()
            if isOpening { self.requestKeyboardFocus?() }
        }

        globalHotKey.onQuickCapture = { [weak self] in
            guard let self else { return }
            guard self.settings.canUseApp else { return }
            self.commandPalette.dismiss()
            self.quickCapture.begin()
            self.notch.tab = .capture
            self.notch.setPinned(true)
            self.notch.expand()
            self.requestKeyboardFocus?()
        }

        globalHotKey.onCommandPalette = { [weak self] in
            self?.presentCommandPalette()
        }

        systemHUD.onPresentation = { [weak self] presentation in
            self?.notch.show(systemHUD: presentation)
        }

        privacyActivity.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                let previous = self.notch.privacyActivity
                self.notch.privacyActivity = state
                guard previous != state else { return }
                self.accessibilityAnnouncements.announce(state.accessibilityValue)
            }
            .store(in: &cancellables)

        // The peek state exists to report live media, so it follows playback.
        // The peek reports whatever is live: playback, or an agent working.
        nowPlaying.$nowPlaying
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .sink { [weak self] isPlaying in
                self?.isPlaying = isPlaying
                self?.refreshLiveActivity()
            }
            .store(in: &cancellables)

        agents.$active
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self] count in
                self?.isAgentWorking = count > 0
                self?.notch.workingAgentCount = count
                self?.refreshLiveActivity()
            }
            .store(in: &cancellables)

        liveActivities.$active
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self] count in
                self?.notch.customLiveActivityCount = count
            }
            .store(in: &cancellables)

        focusTimer.$snapshot
            .map(\.isActive)
            .removeDuplicates()
            .sink { [weak self] isActive in
                self?.notch.hasFocusTimer = isActive
            }
            .store(in: &cancellables)

        meetings.$meeting
            .map { $0?.startsSoon() ?? false }
            .removeDuplicates()
            .sink { [weak self] startsSoon in
                self?.notch.hasUpcomingMeeting = startsSoon
            }
            .store(in: &cancellables)

        meetings.$meeting
            .sink { [weak self] meeting in self?.smartProfiles.updateMeeting(meeting) }
            .store(in: &cancellables)

        events.$latest
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.accessibilityAnnouncements.announce(event: event)
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        metrics.$snapshot
            .sink { [weak self] snapshot in
                self?.systemHUD.updateBattery(snapshot)
                self?.smartProfiles.updatePower(snapshot)
            }
            .store(in: &cancellables)

        settings.$activeProfile
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyWidgetActivation(self.settings.preferences)
                if !self.availableTabs.contains(self.notch.tab) {
                    self.notch.tab = self.availableTabs.first ?? .home
                }
            }
            .store(in: &cancellables)

        // Services are started and stopped as widgets are toggled, so a
        // disabled widget costs nothing at runtime.
        settings.$preferences
            .removeDuplicates()
            .sink { [weak self] preferences in
                self?.applyWidgetActivation(preferences)
            }
            .store(in: &cancellables)

        settings.$licenseAccess
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] access in
                guard let self else { return }
                if access.canUseApp {
                    self.notifications.start()
                    self.smartProfiles.start()
                    self.applyWidgetActivation(self.settings.preferences)
                } else {
                    self.commandPalette.dismiss()
                    self.stopProductServices()
                    self.notch.tab = .home
                    self.notch.setPinned(true)
                    self.notch.expand()
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard settings.canUseApp else {
            notch.setPinned(true)
            notch.expand()
            return
        }
        notifications.start()
        smartProfiles.start()
        applyWidgetActivation(settings.preferences)
    }

    func stop() {
        stopProductServices()
    }

    private func stopProductServices() {
        nowPlaying.stop()
        metrics.stop()
        files.stop()
        clipboard.stop()
        agents.stop()
        liveActivities.stop()
        systemHUD.stop()
        deviceBatteries.stop()
        privacyActivity.stop()
        meetings.stop()
        smartProfiles.stop()
        globalHotKey.stop()
        if focusTimer.snapshot.isActive { focusTimer.cancel() }
    }

    @discardableResult
    func performAppIntentCommand(
        _ action: AppIntentCommand.Action,
        value: String? = nil,
        minutes: Int? = nil
    ) -> Bool {
        guard settings.canUseApp else { return false }
        switch action {
        case .automaticProfiles:
            smartProfiles.useAutomaticMode()
            return true

        case .activateProfile:
            guard let value, let profileID = UUID(uuidString: value),
                  settings.preferences.notchProfiles.contains(where: {
                      $0.id == profileID
                  }) else { return false }
            smartProfiles.activate(profileID)
            return true

        case .createCapture:
            guard settings.preferences.quickCaptureEnabled,
                  let value, quickCapture.capture(value) else { return false }
            showFromAppIntent(.capture)
            accessibilityAnnouncements.announce("Quick Capture saved")
            return true

        case .showWidget:
            guard let value, let tab = NotchTab(rawValue: value),
                  availableTabs.contains(tab) else { return false }
            showFromAppIntent(tab)
            return true

        case .startFocus:
            guard settings.preferences.focusTimerEnabled else { return false }
            focusTimer.start(minutes: minutes ?? 25)
            showFromAppIntent(.home)
            return true
        }
    }

    private func showFromAppIntent(_ tab: NotchTab) {
        commandPalette.dismiss()
        notch.tab = tab
        notch.setPinned(true)
        notch.expand()
    }

    private var isPlaying = false
    private var isAgentWorking = false

    /// `hasLiveActivity` stays about *playback* only; agent work is carried
    /// separately, because the two are gated by different preferences and need
    /// different peek widths.
    private func refreshLiveActivity() {
        notch.hasLiveActivity = isPlaying
    }

    private func applyWidgetActivation(_ preferences: Preferences) {
        guard settings.canUseApp else {
            stopProductServices()
            return
        }

        // Set before starting: it decides whether the first poll scans tabs.
        nowPlaying.includeBrowsers = preferences.browserMediaEnabled
        if settings.isTabEnabled(.music) {
            nowPlaying.start()
        } else {
            nowPlaying.stop()
        }

        if settings.isTabEnabled(.system)
            || preferences.systemHUDEnabled
            || smartProfiles.needsPowerContext {
            metrics.start()
        } else {
            metrics.stop()
        }

        if preferences.systemHUDEnabled {
            systemHUD.start()
        } else {
            systemHUD.stop()
        }

        if settings.isTabEnabled(.system) {
            deviceBatteries.start()
        } else {
            deviceBatteries.stop()
        }

        if preferences.privacyIndicatorsEnabled {
            privacyActivity.start()
        } else {
            privacyActivity.stop()
        }

        accessibilityAnnouncements.isEnabled = preferences.announceImportantUpdates

        let captureHotKeyEnabled = settings.isTabEnabled(.capture)
            && preferences.quickCaptureHotKeyEnabled
        if preferences.globalHotKeyEnabled
            || captureHotKeyEnabled
            || preferences.commandPaletteHotKeyEnabled {
            globalHotKey.start(
                shortcut: preferences.globalHotKeyEnabled ? preferences.globalShortcut : nil,
                quickCaptureShortcut: captureHotKeyEnabled
                    ? preferences.quickCaptureShortcut
                    : nil,
                commandPaletteShortcut: preferences.commandPaletteHotKeyEnabled
                    ? preferences.commandPaletteShortcut
                    : nil
            )
        } else {
            globalHotKey.stop()
        }

        if preferences.upcomingMeetingsEnabled || smartProfiles.needsMeetingContext {
            meetings.start()
        } else {
            meetings.stop()
        }

        if !preferences.focusTimerEnabled, focusTimer.snapshot.isActive {
            focusTimer.cancel()
        }

        if preferences.agentActivityEnabled {
            agents.start()
        } else {
            agents.stop()
        }

        if settings.isTabEnabled(.live) {
            liveActivities.start()
        } else {
            liveActivities.stop()
        }

        if settings.isTabEnabled(.clipboard) {
            clipboard.start()
        } else {
            clipboard.stop()
        }

        if settings.isTabEnabled(.files) {
            files.start()
        } else {
            files.stop()
        }
    }

    /// Tabs the user can actually reach, given their widget toggles.
    var availableTabs: [NotchTab] {
        settings.orderedTabs.filter(settings.isTabEnabled)
    }

    var commandPaletteResults: [CommandPaletteCommand] {
        CommandPaletteCommand.search(commandPalette.query, in: commandPaletteCommands)
    }

    func presentCommandPalette() {
        guard settings.canUseApp else {
            notch.setPinned(true)
            notch.expand()
            return
        }
        commandPalette.present()
        notch.setPinned(true)
        notch.expand()
        requestKeyboardFocus?()
    }

    func executeSelectedCommand() {
        let results = commandPaletteResults
        guard results.indices.contains(commandPalette.selectedIndex) else { return }
        execute(results[commandPalette.selectedIndex])
    }

    func execute(_ command: CommandPaletteCommand) {
        switch command.action {
        case .createCapture:
            commandPalette.dismiss()
            quickCapture.begin()
            notch.tab = .capture
            notch.setPinned(true)
            notch.expand()
            requestKeyboardFocus?()

        case .toggleFocus:
            if focusTimer.snapshot.isRunning {
                focusTimer.pause()
            } else if focusTimer.snapshot.isActive {
                focusTimer.resume()
            } else {
                focusTimer.start(minutes: settings.preferences.defaultFocusMinutes)
            }
            commandPalette.dismiss()

        case let .customAction(id):
            guard let action = settings.preferences.customActions.first(where: { $0.id == id }) else {
                return
            }
            customActions.perform(action, toggleWidget: toggleWidget)
            commandPalette.dismiss()

        case let .clipboard(id):
            guard let item = clipboard.items.first(where: { $0.id == id }) else { return }
            clipboard.copy(item)
            accessibilityAnnouncements.announce("Copied clipboard item")
            commandPalette.dismiss()
            notch.collapse()

        case let .capture(id):
            guard let item = quickCapture.items.first(where: { $0.id == id }) else { return }
            quickCapture.copy(item)
            accessibilityAnnouncements.announce("Copied quick capture")
            commandPalette.dismiss()
            notch.collapse()

        case let .shelf(id):
            guard let item = shelf.items.first(where: { $0.id == id }) else { return }
            shelf.reveal(item)
            commandPalette.dismiss()
            notch.collapse()

        case let .showWidget(tab):
            notch.tab = tab
            commandPalette.dismiss()

        case let .activateProfile(id):
            smartProfiles.activate(id)
            commandPalette.dismiss()
            if let profile = settings.preferences.notchProfiles.first(where: { $0.id == id }) {
                accessibilityAnnouncements.announce("Switched to \(profile.displayName) profile")
            }

        case .automaticProfiles:
            smartProfiles.useAutomaticMode()
            commandPalette.dismiss()
            accessibilityAnnouncements.announce("Automatic profiles enabled")

        case .disableProfiles:
            smartProfiles.turnOff()
            commandPalette.dismiss()
            accessibilityAnnouncements.announce("Smart profiles off")

        case let .openSettings(page):
            commandPalette.dismiss()
            notch.collapse()
            requestSettingsPage?(page)
        }
    }

    private var commandPaletteCommands: [CommandPaletteCommand] {
        var commands: [CommandPaletteCommand] = []

        if settings.isTabEnabled(.capture) {
            commands.append(CommandPaletteCommand(
                id: "capture-new",
                title: "Create quick capture",
                subtitle: "Save a note or link",
                systemImage: "square.and.pencil",
                category: "Action",
                keywords: ["new", "note", "write", "save"],
                priority: 0,
                action: .createCapture
            ))
        }

        if settings.preferences.focusTimerEnabled {
            let focusTitle: String
            let focusSubtitle: String
            if focusTimer.snapshot.isRunning {
                focusTitle = "Pause focus timer"
                focusSubtitle = focusTimer.snapshot.timeString + " remaining"
            } else if focusTimer.snapshot.isActive {
                focusTitle = "Resume focus timer"
                focusSubtitle = focusTimer.snapshot.timeString + " remaining"
            } else {
                focusTitle = "Start focus timer"
                focusSubtitle = "Focus for \(settings.preferences.defaultFocusMinutes) minutes"
            }
            commands.append(CommandPaletteCommand(
                id: "focus-toggle",
                title: focusTitle,
                subtitle: focusSubtitle,
                systemImage: "timer",
                category: "Action",
                keywords: ["pomodoro", "work", "pause", "resume"],
                priority: 1,
                action: .toggleFocus
            ))
        }

        if settings.isTabEnabled(.shortcuts) {
            commands += settings.preferences.customActions.enumerated().map { index, action in
                CommandPaletteCommand(
                    id: "action-\(action.id.uuidString)",
                    title: action.title,
                    subtitle: action.subtitle,
                    systemImage: action.systemImage,
                    category: "Shortcut",
                    keywords: ["app", "shortcut", "run", "open", "toggle"],
                    priority: 10 + index,
                    action: .customAction(action.id)
                )
            }
        }

        commands += availableTabs.enumerated().map { index, tab in
            CommandPaletteCommand(
                id: "widget-\(tab.rawValue)",
                title: "Show \(tab.title)",
                subtitle: "Switch to the \(tab.title) widget",
                systemImage: tab.systemImage,
                category: "Widget",
                keywords: [tab.rawValue, "tab", "open", "switch"],
                priority: 30 + index,
                action: .showWidget(tab)
            )
        }

        if settings.isTabEnabled(.clipboard) {
            commands += clipboard.items.enumerated().map { index, item in
                CommandPaletteCommand(
                    id: "clipboard-\(item.id.uuidString)",
                    title: item.title,
                    subtitle: "Copy from Clipboard · \(item.detail)",
                    systemImage: item.systemImage,
                    category: "Clipboard",
                    keywords: ["paste", "copy", "history"],
                    priority: 50 + index,
                    action: .clipboard(item.id)
                )
            }
        }

        if settings.isTabEnabled(.capture) {
            commands += quickCapture.items.enumerated().map { index, item in
                CommandPaletteCommand(
                    id: "capture-\(item.id.uuidString)",
                    title: item.title,
                    subtitle: "Copy from Quick Capture · \(item.detail)",
                    systemImage: item.isLink ? "link" : "note.text",
                    category: "Capture",
                    keywords: ["note", "saved", "copy"],
                    priority: 60 + index,
                    action: .capture(item.id)
                )
            }
        }

        if settings.isTabEnabled(.shelf) {
            commands += shelf.items.enumerated().map { index, item in
                CommandPaletteCommand(
                    id: "shelf-\(item.id.uuidString)",
                    title: item.name,
                    subtitle: "Reveal shelf item in Finder",
                    systemImage: "doc.fill",
                    category: "Shelf",
                    keywords: ["file", "finder", "reveal"],
                    priority: 70 + index,
                    action: .shelf(item.id)
                )
            }
        }

        if settings.preferences.smartProfileMode != .automatic {
            commands.append(CommandPaletteCommand(
                id: "profiles-automatic",
                title: "Use Automatic Profiles",
                subtitle: "Switch profiles when your context changes",
                systemImage: "wand.and.stars",
                category: "Profile",
                keywords: ["smart", "context", "mode"],
                priority: 80,
                action: .automaticProfiles
            ))
        }

        commands += settings.preferences.notchProfiles.enumerated().map { index, profile in
            CommandPaletteCommand(
                id: "profile-\(profile.id.uuidString)",
                title: "Switch to \(profile.displayName) Profile",
                subtitle: settings.activeProfile?.id == profile.id
                    ? "Currently active"
                    : "Use its widgets and appearance",
                systemImage: profile.systemImage,
                category: "Profile",
                keywords: ["smart", "mode", profile.displayName],
                priority: 81 + index,
                action: .activateProfile(profile.id)
            )
        }

        if settings.preferences.smartProfileMode != .off {
            commands.append(CommandPaletteCommand(
                id: "profiles-off",
                title: "Turn Smart Profiles Off",
                subtitle: "Restore your standard notch setup",
                systemImage: "circle.slash",
                category: "Profile",
                keywords: ["disable", "default", "mode"],
                priority: 89,
                action: .disableProfiles
            ))
        }

        commands += SettingsPage.allCases.enumerated().map { index, page in
            CommandPaletteCommand(
                id: "settings-\(page.rawValue)",
                title: "Open \(page.title) settings",
                subtitle: page.subtitle,
                systemImage: page.systemImage,
                category: "Settings",
                keywords: ["preferences", page.rawValue],
                priority: 110 + index,
                action: .openSettings(page)
            )
        }

        return commands
    }

    /// Returns the widget's new enabled state, or nil for tabs that are not
    /// independently toggleable. Custom actions call this instead of carrying
    /// writable key paths or mutating preferences themselves.
    @discardableResult
    func toggleWidget(_ tab: NotchTab) -> Bool? {
        if let activeProfile = settings.activeProfile,
           let profileIndex = settings.preferences.notchProfiles.firstIndex(where: {
               $0.id == activeProfile.id
           }) {
            guard tab != .home, tab != .shortcuts else { return nil }
            let isEnabled = settings.preferences.notchProfiles[profileIndex]
                .enabledTabs.contains(tab)
            if isEnabled {
                settings.preferences.notchProfiles[profileIndex].enabledTabs.removeAll { $0 == tab }
            } else {
                settings.preferences.notchProfiles[profileIndex].enabledTabs.append(tab)
            }
            return !isEnabled
        }

        let newValue: Bool
        switch tab {
        case .music:
            newValue = !settings.preferences.musicWidgetEnabled
            settings.preferences.musicWidgetEnabled = newValue
        case .system:
            newValue = !settings.preferences.systemWidgetEnabled
            settings.preferences.systemWidgetEnabled = newValue
        case .live:
            newValue = !settings.preferences.customLiveActivitiesEnabled
            settings.preferences.customLiveActivitiesEnabled = newValue
        case .files:
            newValue = !settings.preferences.fileActivityEnabled
            settings.preferences.fileActivityEnabled = newValue
        case .activity:
            newValue = !settings.preferences.activityFeedEnabled
            settings.preferences.activityFeedEnabled = newValue
        case .clipboard:
            newValue = !settings.preferences.clipboardHistoryEnabled
            settings.preferences.clipboardHistoryEnabled = newValue
        case .capture:
            newValue = !settings.preferences.quickCaptureEnabled
            settings.preferences.quickCaptureEnabled = newValue
        case .shelf:
            newValue = !settings.preferences.shelfEnabled
            settings.preferences.shelfEnabled = newValue
        case .home, .shortcuts:
            return nil
        }
        return newValue
    }
}
