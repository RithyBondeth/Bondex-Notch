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
    let files: FileActivityService
    let shelf: ShelfService
    let agents: AgentActivityService
    let liveActivities: LiveActivityService
    let notifications: NotificationService
    let notch: NotchViewModel

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
        self.files = FileActivityService(events: events)
        self.shelf = ShelfService(events: events)
        self.agents = AgentActivityService(events: events)
        self.liveActivities = LiveActivityService(events: events)
        self.notifications = NotificationService(events: events)
        self.notch = NotchViewModel(settings: settings, events: events, screen: screen)

        wire()
    }

    private func wire() {
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
