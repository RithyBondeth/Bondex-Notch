import AppIntents
import Foundation

/// Registers this Swift package target with the App Intents build-time indexer.
struct BondexNotchIntentsPackage: AppIntentsPackage { }

private struct BondexIntentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum BondexProfileIntentOption: String, AppEnum {
    case work
    case meeting
    case media
    case gaming

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Notch Profile")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .work: "Work",
        .meeting: "Meeting",
        .media: "Media",
        .gaming: "Gaming"
    ]

    var profileID: UUID {
        switch self {
        case .work: return UUID(uuidString: "99C206C1-D819-4DA3-97F4-87C8FDE7A101")!
        case .meeting: return UUID(uuidString: "99C206C1-D819-4DA3-97F4-87C8FDE7A102")!
        case .media: return UUID(uuidString: "99C206C1-D819-4DA3-97F4-87C8FDE7A103")!
        case .gaming: return UUID(uuidString: "99C206C1-D819-4DA3-97F4-87C8FDE7A104")!
        }
    }
}

enum BondexWidgetIntentOption: String, AppEnum {
    case home
    case capture
    case shortcuts
    case music
    case system
    case live
    case files
    case activity
    case clipboard
    case shelf

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Notch Widget")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .home: "Home",
        .capture: "Capture",
        .shortcuts: "Shortcuts",
        .music: "Music",
        .system: "System",
        .live: "Live Activities",
        .files: "Files",
        .activity: "Activity",
        .clipboard: "Clipboard",
        .shelf: "Shelf"
    ]
}

struct UseAutomaticProfilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Use Automatic Notch Profiles"
    static let description = IntentDescription(
        "Switches Bondex Notch profiles automatically as your context changes."
    )
    static let openAppWhenRun = true
    @Dependency private var environment: AppEnvironment

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        environment.performAppIntentCommand(.automaticProfiles)
        return .result(dialog: "Automatic notch profiles are on.")
    }
}

struct SwitchNotchProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Notch Profile"
    static let description = IntentDescription("Activates a Bondex Notch profile.")
    static let openAppWhenRun = true

    @Parameter(title: "Profile") var profile: BondexProfileIntentOption
    @Dependency private var environment: AppEnvironment

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard environment.performAppIntentCommand(
            .activateProfile,
            value: profile.profileID.uuidString
        ) else {
            throw BondexIntentError(message: "That profile is no longer available.")
        }
        return .result(dialog: "Switched to the \(profile.rawValue) profile.")
    }
}

struct CreateNotchCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Notch Capture"
    static let description = IntentDescription(
        "Saves a short note or link in Bondex Notch."
    )
    static let openAppWhenRun = true

    @Parameter(title: "Text", requestValueDialog: "What would you like to capture?")
    var text: String
    @Dependency private var environment: AppEnvironment

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 10_000 else {
            throw $text.needsValueError("Enter a note between 1 and 10,000 characters.")
        }
        guard environment.performAppIntentCommand(.createCapture, value: normalized) else {
            throw BondexIntentError(message: "Quick Capture is unavailable.")
        }
        return .result(dialog: "Saved to Quick Capture.")
    }
}

struct StartNotchFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Notch Focus Timer"
    static let description = IntentDescription("Starts a focus session in Bondex Notch.")
    static let openAppWhenRun = true

    @Parameter(title: "Minutes", default: 25, inclusiveRange: (1, 180))
    var minutes: Int
    @Dependency private var environment: AppEnvironment

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let duration = min(max(minutes, 1), 180)
        guard environment.performAppIntentCommand(.startFocus, minutes: duration) else {
            throw BondexIntentError(message: "The focus timer is disabled in Bondex Notch.")
        }
        return .result(dialog: "Started a \(duration)-minute focus session.")
    }
}

struct ShowNotchWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Notch Widget"
    static let description = IntentDescription("Opens a widget in Bondex Notch.")
    static let openAppWhenRun = true

    @Parameter(title: "Widget") var widget: BondexWidgetIntentOption
    @Dependency private var environment: AppEnvironment

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard environment.performAppIntentCommand(.showWidget, value: widget.rawValue) else {
            throw BondexIntentError(message: "That widget is disabled or unavailable.")
        }
        return .result(dialog: "Opened the \(widget.rawValue) widget.")
    }
}

struct BondexNotchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UseAutomaticProfilesIntent(),
            phrases: [
                "Use automatic profiles in \(.applicationName)",
                "Automatically switch \(.applicationName) profiles"
            ],
            shortTitle: "Automatic Profiles",
            systemImageName: "wand.and.stars"
        )
        AppShortcut(
            intent: SwitchNotchProfileIntent(),
            phrases: [
                "Switch profile in \(.applicationName)",
                "Use a profile in \(.applicationName)"
            ],
            shortTitle: "Switch Profile",
            systemImageName: "circle.grid.2x2.fill"
        )
        AppShortcut(
            intent: CreateNotchCaptureIntent(),
            phrases: [
                "Capture something in \(.applicationName)",
                "Create a quick capture in \(.applicationName)"
            ],
            shortTitle: "Quick Capture",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: StartNotchFocusIntent(),
            phrases: [
                "Start a focus timer in \(.applicationName)",
                "Focus with \(.applicationName)"
            ],
            shortTitle: "Start Focus",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: ShowNotchWidgetIntent(),
            phrases: [
                "Show a widget in \(.applicationName)",
                "Open a widget in \(.applicationName)"
            ],
            shortTitle: "Show Widget",
            systemImageName: "rectangle.topthird.inset.filled"
        )
    }
}
