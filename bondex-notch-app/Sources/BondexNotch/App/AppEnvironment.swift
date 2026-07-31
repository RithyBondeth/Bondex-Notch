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
    let files: FileActivityService
    let shelf: ShelfService
    let agents: AgentActivityService
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
        self.files = FileActivityService(events: events)
        self.shelf = ShelfService(events: events)
        self.agents = AgentActivityService(events: events)
        self.notifications = NotificationService(events: events)
        self.notch = NotchViewModel(settings: settings, events: events, screen: screen)

        wire()
    }

    private func wire() {
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
            .map { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] isWorking in
                self?.isAgentWorking = isWorking
                self?.notch.hasAgentActivity = isWorking
                self?.refreshLiveActivity()
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

        if preferences.systemWidgetEnabled {
            metrics.start()
        } else {
            metrics.stop()
        }

        if preferences.agentActivityEnabled {
            agents.start()
        } else {
            agents.stop()
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
        NotchTab.allCases.filter { tab in
            switch tab {
            case .home: return true
            case .music: return settings.preferences.musicWidgetEnabled
            case .files: return settings.preferences.fileActivityEnabled
            case .activity: return settings.preferences.activityFeedEnabled
            case .shelf: return settings.preferences.shelfEnabled
            }
        }
    }
}
