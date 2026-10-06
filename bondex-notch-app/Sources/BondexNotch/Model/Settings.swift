import Combine
import Foundation
import ServiceManagement
import SwiftUI

/// User preferences, persisted to `UserDefaults` as a single JSON blob.
///
/// One blob keeps migrations trivial and means a service only has to observe a
/// single publisher to react to any preference change.
struct Preferences: Codable, Equatable {
    var accent: Theme.Accent = .graphite
    var customAccentHex = "6EA8FF"
    var panelStyle: Theme.PanelStyle = .gradient
    var panelWidth: Double = 520
    var panelOpacity: Double = 1
    var bottomCornerRadius: Double = Double(Theme.bottomRadius)
    var flareRadius: Double = Double(Theme.flareRadius)
    var rimStrength: Double = 1
    var shadowStrength: Double = 1
    var motionSpeed: Motion.Speed = .standard

    var musicWidgetEnabled = true
    var systemWidgetEnabled = true
    /// Show compact notch feedback when a hardware control changes.
    var systemHUDEnabled = true
    /// Show a persistent compact indicator while a camera or microphone is active.
    var privacyIndicatorsEnabled = true
    /// How long transient hardware feedback remains visible.
    var systemHUDDuration = 1.65
    /// Keep a compact copy of the System tab's gauges on Home.
    var showSystemSummaryOnHome = false
    var fileActivityEnabled = true
    var activityFeedEnabled = true
    var clipboardHistoryEnabled = true
    var quickCaptureEnabled = true
    /// User-triggered only. Capture text remains on device when the system
    /// Apple Intelligence model is available.
    var appleIntelligenceCaptureEnabled = true
    var customShortcutsEnabled = true
    var customActions: [CustomAction] = []
    var shelfEnabled = true
    /// Show a mark beside the notch while Claude Code or Codex is working.
    var agentActivityEnabled = true
    /// The Agents tab: plan limits, spend and trends read from local agent logs.
    var agentUsageEnabled = true
    var agentUsageRange: UsageRange = .today
    var customLiveActivitiesEnabled = true
    var focusTimerEnabled = true
    var defaultFocusMinutes = 25
    var upcomingMeetingsEnabled = false
    /// Compact peeks may be visible while screen sharing; titles are private by default.
    var showMeetingTitlesInPeek = false
    /// Order of the tabs in the expanded panel. Unknown or missing tabs are
    /// repaired by `SettingsStore` so upgrades never strand a new widget.
    var widgetOrder: [NotchTab] = NotchTab.allCases

    var smartProfileMode: SmartProfileMode = .off
    var selectedProfileID: UUID? = UUID(
        uuidString: "99C206C1-D819-4DA3-97F4-87C8FDE7A101"
    )
    var notchProfiles: [NotchProfile] = NotchProfile.defaults

    /// Expand when the pointer rests on the notch, versus requiring a click.
    var expandOnHover = true
    /// How long the pointer has to dwell on the notch before it opens.
    ///
    /// Without this the panel fires open every time the pointer crosses the top
    /// of the screen on its way to the menu bar, which is the single biggest
    /// source of "it feels twitchy".
    var hoverDelay: Double = 0.18
    /// Grace period before the panel closes after the pointer leaves.
    var closeDelay: Double = 0.3
    /// Show a compact "peek" (album art + waveform) beside the notch while media plays.
    var peekWhilePlaying = true
    /// Read media out of browser tabs as well as Music and Spotify. This is what
    /// makes YouTube and other web players show up.
    var browserMediaEnabled = true

    /// A permission-free registered chord, not a global key logger.
    var globalHotKeyEnabled = true
    var globalShortcut: GlobalShortcut = .controlOptionSpace
    var quickCaptureHotKeyEnabled = true
    var quickCaptureShortcut: QuickCaptureShortcut = .controlOptionC
    var commandPaletteHotKeyEnabled = true
    var commandPaletteShortcut: CommandPaletteShortcut = .controlOptionP
    var announceImportantUpdates = true

    var downloadsFolderBookmark: Data?
    var launchAtLogin = false
    var showNotchOnExternalDisplays = true
}

@MainActor
final class SettingsStore: ObservableObject {
    private static let defaultsKey = "com.bondex.notch.preferences"

    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            persist()
            if preferences.launchAtLogin != oldValue.launchAtLogin, !isRevertingLoginItem {
                applyLaunchAtLogin(preferences.launchAtLogin)
            }
            preferencesSubject.send(preferences)
        }
    }

    /// Surfaced in Settings when macOS refuses to register the login item
    /// (common for ad-hoc signed local builds).
    @Published var launchAtLoginError: String?
    @Published private(set) var activeProfile: NotchProfile? {
        didSet {
            guard activeProfile != oldValue else { return }
            activeProfileSubject.send(activeProfile)
        }
    }

    /// Emits after `preferences` has been stored.
    ///
    /// `$preferences` fires from `willSet`, so a subscriber that reads the store
    /// again — directly, or through `isTabEnabled`, `activeProfile`-aware
    /// helpers, or another service — sees the *previous* value. That made every
    /// toggle apply one change late: turning a widget on started nothing, and
    /// turning it off again started it. Subscribers that react to a change by
    /// consulting the store must use this instead.
    var preferencesDidChange: AnyPublisher<Preferences, Never> {
        preferencesSubject.eraseToAnyPublisher()
    }

    /// The `activeProfile` counterpart of `preferencesDidChange`.
    var activeProfileDidChange: AnyPublisher<NotchProfile?, Never> {
        activeProfileSubject.eraseToAnyPublisher()
    }

    private let preferencesSubject = PassthroughSubject<Preferences, Never>()
    private let activeProfileSubject = PassthroughSubject<NotchProfile?, Never>()

    private let defaults: UserDefaults
    /// Guards the write-back that undoes a failed login-item registration, so
    /// the revert does not re-enter `applyLaunchAtLogin` and clear the error.
    private var isRevertingLoginItem = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedPreferences = defaults.data(forKey: Self.defaultsKey)
            .flatMap(Self.decode) ?? Preferences()
        preferences = loadedPreferences
    }

    /// Decodes a stored blob, tolerating one written by a different version.
    ///
    /// `Preferences` is persisted as a single JSON object, and the synthesized
    /// decoder treats *any* missing key as an error — so shipping one new
    /// preference would throw on every existing install and silently reset every
    /// setting the user had chosen. Merging the stored values over a freshly
    /// encoded default gives new fields their default and keeps everything the
    /// user actually set, in both directions: fields that go away are ignored
    /// rather than fatal.
    static func decode(_ data: Data) -> Preferences? {
        guard let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultData = try? JSONEncoder().encode(Preferences()),
              var merged = try? JSONSerialization.jsonObject(with: defaultData) as? [String: Any]
        else {
            return try? JSONDecoder().decode(Preferences.self, from: data)
        }

        merged.merge(stored) { _, stored in stored }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else {
            return nil
        }
        return try? JSONDecoder().decode(Preferences.self, from: mergedData)
    }

    var effectiveAccent: Theme.Accent {
        activeProfile?.accent ?? preferences.accent
    }

    var effectiveAccentColor: Color {
        let accent = effectiveAccent
        guard accent == .custom else { return accent.color }
        return Color(hexRGB: preferences.customAccentHex) ?? Theme.Accent.graphite.color
    }

    var orderedTabs: [NotchTab] {
        if let activeProfile { return activeProfile.orderedTabs }
        return standardOrderedTabs
    }

    /// The order used when no profile is active — what Settings › Widgets
    /// edits, whatever profile happens to be in force.
    var standardOrderedTabs: [NotchTab] {
        var seen = Set<NotchTab>()
        var result = preferences.widgetOrder.filter { seen.insert($0).inserted }

        // Insert tabs introduced by a newer release beside their canonical
        // neighbour instead of dumping them at the end of a user's saved order,
        // while preserving every move the user already made among existing tabs.
        for tab in NotchTab.allCases where !seen.contains(tab) {
            let canonical = NotchTab.allCases
            let tabIndex = canonical.firstIndex(of: tab)!
            let predecessor = canonical[..<tabIndex].reversed().first { result.contains($0) }
            if let predecessor, let index = result.firstIndex(of: predecessor) {
                result.insert(tab, at: index + 1)
            } else {
                result.insert(tab, at: 0)
            }
            seen.insert(tab)
        }
        return result
    }

    var effectivePanelWidth: Double {
        activeProfile?.panelWidth ?? preferences.panelWidth
    }

    var effectivePanelStyle: Theme.PanelStyle {
        activeProfile?.panelStyle ?? preferences.panelStyle
    }

    func isTabEnabled(_ tab: NotchTab) -> Bool {
        if let activeProfile {
            return tab == .home || activeProfile.enabledTabs.contains(tab)
        }
        switch tab {
        case .home: return true
        case .agents: return preferences.agentUsageEnabled
        case .capture: return preferences.quickCaptureEnabled
        case .shortcuts: return preferences.customShortcutsEnabled
        case .music: return preferences.musicWidgetEnabled
        case .system: return preferences.systemWidgetEnabled
        case .live: return preferences.customLiveActivitiesEnabled
        case .files: return preferences.fileActivityEnabled
        case .activity: return preferences.activityFeedEnabled
        case .clipboard: return preferences.clipboardHistoryEnabled
        case .shelf: return preferences.shelfEnabled
        }
    }

    func setActiveProfile(_ profile: NotchProfile?) {
        guard activeProfile != profile else { return }
        activeProfile = profile
    }

    func resetAppearance() {
        let defaults = Preferences()
        preferences.accent = defaults.accent
        preferences.customAccentHex = defaults.customAccentHex
        preferences.panelStyle = defaults.panelStyle
        preferences.panelWidth = defaults.panelWidth
        preferences.panelOpacity = defaults.panelOpacity
        preferences.bottomCornerRadius = defaults.bottomCornerRadius
        preferences.flareRadius = defaults.flareRadius
        preferences.rimStrength = defaults.rimStrength
        preferences.shadowStrength = defaults.shadowStrength
        preferences.motionSpeed = defaults.motionSpeed
    }

    var motion: Motion.Speed { preferences.motionSpeed }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            Log.app.error("Launch at login toggle failed: \(error.localizedDescription)")
            launchAtLoginError = error.localizedDescription
            // Reflect reality: the switch should not claim success.
            if enabled {
                isRevertingLoginItem = true
                preferences.launchAtLogin = false
                isRevertingLoginItem = false
            }
        }
    }
}
