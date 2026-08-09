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
    let dev: DevProjectService
    let shelf: ShelfService
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
        self.dev = DevProjectService(events: events)
        self.shelf = ShelfService(events: events)
        self.notifications = NotificationService(events: events)
        self.notch = NotchViewModel(settings: settings, events: events, screen: screen)

        wire()
    }

    private func wire() {
        // The peek state exists to report live media, so it follows playback.
        nowPlaying.$nowPlaying
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .sink { [weak self] isPlaying in
                self?.notch.hasLiveActivity = isPlaying
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
        dev.stop()
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

        let filesUnlocked = preferences.tier == .pro
        if preferences.fileActivityEnabled && filesUnlocked {
            files.start()
        } else {
            files.stop()
        }

        // Restarted on any change to the path as well as the toggle, since the
        // watcher is bound to one directory.
        if preferences.devWidgetEnabled, preferences.tier == .pro {
            if preferences.devProjectPath != startedDevPath {
                startedDevPath = preferences.devProjectPath
                dev.start(path: preferences.devProjectPath)
            }
        } else if startedDevPath != nil {
            startedDevPath = nil
            dev.stop()
        }
    }

    /// The path the dev watcher is currently bound to, so an unrelated preference
    /// change does not tear down and rebuild it.
    private var startedDevPath: String?

    /// Tabs the user can actually reach, given their tier and widget toggles.
    var availableTabs: [NotchTab] {
        NotchTab.allCases.filter { tab in
            switch tab {
            case .home: return true
            case .music: return settings.preferences.musicWidgetEnabled
            case .dev: return settings.preferences.devWidgetEnabled
            case .files: return settings.preferences.fileActivityEnabled
            case .activity: return settings.preferences.activityFeedEnabled
            case .shelf: return settings.preferences.shelfEnabled
            }
        }
    }
}
