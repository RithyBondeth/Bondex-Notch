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
    /// How long transient hardware feedback remains visible.
    var systemHUDDuration = 1.65
    /// Keep a compact copy of the System tab's gauges on Home.
    var showSystemSummaryOnHome = false
    var fileActivityEnabled = true
    var activityFeedEnabled = true
    var clipboardHistoryEnabled = true
    var shelfEnabled = true
    /// Show a mark beside the notch while Claude Code or Codex is working.
    var agentActivityEnabled = true
    var customLiveActivitiesEnabled = true
    var focusTimerEnabled = true
    var defaultFocusMinutes = 25
    var upcomingMeetingsEnabled = false
    /// Compact peeks may be visible while screen sharing; titles are private by default.
    var showMeetingTitlesInPeek = false
    /// Order of the tabs in the expanded panel. Unknown or missing tabs are
    /// repaired by `SettingsStore` so upgrades never strand a new widget.
    var widgetOrder: [NotchTab] = NotchTab.allCases

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
    var announceImportantUpdates = true

    var downloadsFolderBookmark: Data?
    var launchAtLogin = false

    var licenseKey: String = ""

    var tier: LicenseTier {
        LicenseValidator.validate(licenseKey) ? .pro : .free
    }
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
        }
    }

    /// Surfaced in Settings when macOS refuses to register the login item
    /// (common for ad-hoc signed local builds).
    @Published var launchAtLoginError: String?

    private let defaults: UserDefaults
    /// Guards the write-back that undoes a failed login-item registration, so
    /// the revert does not re-enter `applyLaunchAtLogin` and clear the error.
    private var isRevertingLoginItem = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = defaults.data(forKey: Self.defaultsKey)
            .flatMap(Self.decode) ?? Preferences()
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

    var tier: LicenseTier { preferences.tier }

    /// Every Pro feature unlocks together today. This stays keyed by feature so
    /// a future tier split is a change here rather than at each call site.
    func isUnlocked(_ feature: ProFeature) -> Bool {
        tier == .pro
    }

    /// Accent falls back to the free accent when Pro lapses, so a downgraded
    /// user never gets stuck looking at a locked theme.
    var effectiveAccent: Theme.Accent {
        let accent = preferences.accent
        if accent.requiresPro && tier != .pro { return .graphite }
        return accent
    }

    var effectiveAccentColor: Color {
        let accent = effectiveAccent
        guard accent == .custom else { return accent.color }
        return Color(hexRGB: preferences.customAccentHex) ?? Theme.Accent.graphite.color
    }

    var orderedTabs: [NotchTab] {
        var seen = Set<NotchTab>()
        var result = preferences.widgetOrder.filter { seen.insert($0).inserted }

        // Insert tabs introduced by a newer release beside their canonical
        // neighbour instead of dumping them at the end of a user's saved order.
        // This puts the new System tab after Music while preserving every move
        // the user already made among their existing tabs.
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
