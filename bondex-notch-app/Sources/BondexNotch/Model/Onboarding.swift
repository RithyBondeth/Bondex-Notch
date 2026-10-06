import Foundation

/// What the welcome screen lets someone choose, and what each choice will ask
/// macOS for.
///
/// A value type over `Preferences`, so the screen can be backed out of without
/// having changed anything, and so the rules are testable without a window.
struct OnboardingChoices: Equatable {
    var media: Bool
    var agents: Bool
    var clipboard: Bool
    var downloads: Bool
    var meetings: Bool
    var agentNotifications: Bool

    init(preferences: Preferences) {
        media = preferences.musicWidgetEnabled
        agents = preferences.agentActivityEnabled && preferences.agentUsageEnabled
        clipboard = preferences.clipboardHistoryEnabled
        downloads = preferences.fileActivityEnabled
        meetings = preferences.upcomingMeetingsEnabled
        agentNotifications = preferences.notifyWhenAgentNeedsYou
            || preferences.notifyWhenAgentRunFinishes
    }

    /// Writes the choices into `preferences` and marks the welcome as done.
    func apply(to preferences: inout Preferences) {
        preferences.musicWidgetEnabled = media
        preferences.agentActivityEnabled = agents
        preferences.agentUsageEnabled = agents
        preferences.clipboardHistoryEnabled = clipboard
        preferences.fileActivityEnabled = downloads
        preferences.upcomingMeetingsEnabled = meetings
        preferences.notifyWhenAgentNeedsYou = agents && agentNotifications
        preferences.notifyWhenAgentRunFinishes = agents && agentNotifications
        preferences.hasCompletedOnboarding = true
    }

    enum Permission: Equatable {
        case calendar
        case notifications
        /// macOS 15.4 and later ask before an app reads the clipboard.
        case clipboard
    }

    /// Permissions to ask for as soon as the choices are applied.
    ///
    /// Automation and Downloads are not here: macOS asks for those by itself
    /// the first time a chosen feature reads a player or the folder, which is
    /// already the right moment — and asking for Automation up front is not
    /// possible, since it is granted per app.
    static var clipboardNeedsPermission: Bool {
        if #available(macOS 15.4, *) { return true }
        return false
    }

    var permissionsToRequest: [Permission] {
        var permissions: [Permission] = []
        if meetings { permissions.append(.calendar) }
        if agents && agentNotifications { permissions.append(.notifications) }
        if clipboard, Self.clipboardNeedsPermission { permissions.append(.clipboard) }
        return permissions
    }
}

/// One row of the welcome screen's feature list.
struct OnboardingFeature: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    /// What macOS will ask for, in plain words, or nil when nothing.
    let asks: String?
    let choice: WritableKeyPath<OnboardingChoices, Bool>

    static var all: [OnboardingFeature] { [
        OnboardingFeature(
            id: "media",
            title: "Music and video",
            detail: "What's playing in Music, Spotify and browser tabs, with controls.",
            systemImage: "music.note",
            asks: "Asks to control each player the first time it reads one",
            choice: \.media
        ),
        OnboardingFeature(
            id: "agents",
            title: "Coding agents",
            detail: "Claude Code and Codex working, waiting for you, and their usage.",
            systemImage: "terminal.fill",
            asks: nil,
            choice: \.agents
        ),
        OnboardingFeature(
            id: "notifications",
            title: "Tell me when an agent needs me",
            detail: "A notification when one has waited 20 seconds, or a long run ends.",
            systemImage: "bell.badge.fill",
            asks: "Asks to send notifications",
            choice: \.agentNotifications
        ),
        OnboardingFeature(
            id: "clipboard",
            title: "Clipboard history",
            detail: "Recent copies, kept in memory only and never written to disk.",
            systemImage: "doc.on.clipboard.fill",
            asks: OnboardingChoices.clipboardNeedsPermission
                ? "Asks to read what you copy"
                : nil,
            choice: \.clipboard
        ),
        OnboardingFeature(
            id: "downloads",
            title: "Downloads",
            detail: "Transfers landing in your Downloads folder.",
            systemImage: "arrow.down.circle.fill",
            asks: "Asks to read your Downloads folder",
            choice: \.downloads
        ),
        OnboardingFeature(
            id: "meetings",
            title: "Upcoming meetings",
            detail: "Your next meeting beside the notch, with a Join button.",
            systemImage: "calendar",
            asks: "Asks for calendar access",
            choice: \.meetings
        )
    ] }
}
