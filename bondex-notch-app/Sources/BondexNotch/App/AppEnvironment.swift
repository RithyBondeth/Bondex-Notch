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
    let focusTimer: FocusTimerService
    let meetings: UpcomingMeetingService
    let globalHotKey: GlobalHotKeyService
    let accessibilityAnnouncements: AccessibilityAnnouncementService
    let files: FileActivityService
    let shelf: ShelfService
    let agents: AgentActivityService
    let liveActivities: LiveActivityService
    let notifications: NotificationService
    let notch: NotchViewModel

    /// Installed by the window controller so a global shortcut can make the
    /// nonactivating panel keyboard-operable without activating the whole app.
    var requestKeyboardFocus: (() -> Void)?

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
        self.focusTimer = FocusTimerService(defaults: defaults, events: events)
        self.meetings = UpcomingMeetingService()
        self.globalHotKey = GlobalHotKeyService()
        self.accessibilityAnnouncements = AccessibilityAnnouncementService()
        self.files = FileActivityService(events: events)
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
            let isOpening = !self.notch.state.isExpanded
            self.notch.toggle()
            if isOpening { self.requestKeyboardFocus?() }
        }

        systemHUD.onPresentation = { [weak self] presentation in
            self?.notch.show(systemHUD: presentation)
        }

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
    }

    func start() {
        notifications.start()
        applyWidgetActivation(settings.preferences)
    }

    func stop() {
        nowPlaying.stop()
        metrics.stop()
        files.stop()
        agents.stop()
        liveActivities.stop()
        systemHUD.stop()
        meetings.stop()
        globalHotKey.stop()
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
        // Set before starting: it decides whether the first poll scans tabs.
        nowPlaying.includeBrowsers = preferences.browserMediaEnabled
        if preferences.musicWidgetEnabled {
            nowPlaying.start()
        } else {
            nowPlaying.stop()
        }

        if preferences.systemWidgetEnabled || preferences.systemHUDEnabled {
            metrics.start()
        } else {
            metrics.stop()
        }

        if preferences.systemHUDEnabled {
            systemHUD.start()
        } else {
            systemHUD.stop()
        }

        accessibilityAnnouncements.isEnabled = preferences.announceImportantUpdates

        if preferences.globalHotKeyEnabled {
            globalHotKey.start(shortcut: preferences.globalShortcut)
        } else {
            globalHotKey.stop()
        }

        if preferences.upcomingMeetingsEnabled {
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

        if preferences.customLiveActivitiesEnabled {
            liveActivities.start()
        } else {
            liveActivities.stop()
        }

        let filesUnlocked = preferences.tier == .pro
        if preferences.fileActivityEnabled && filesUnlocked {
            files.start()
        } else {
            files.stop()
        }
    }

    /// Tabs the user can actually reach, given their tier and widget toggles.
    var availableTabs: [NotchTab] {
        settings.orderedTabs.filter { tab in
            switch tab {
            case .home: return true
            case .music: return settings.preferences.musicWidgetEnabled
            case .system: return settings.preferences.systemWidgetEnabled
            case .live: return settings.preferences.customLiveActivitiesEnabled
            case .files: return settings.preferences.fileActivityEnabled
            case .activity: return settings.preferences.activityFeedEnabled
            case .shelf: return settings.preferences.shelfEnabled
            }
        }
    }
}
