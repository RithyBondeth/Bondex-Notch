import Foundation

enum SmartProfileMode: String, CaseIterable, Codable, Identifiable {
    case off
    case automatic
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .automatic: return "Automatic"
        case .manual: return "Manual"
        }
    }
}

enum ProfilePowerCondition: String, CaseIterable, Codable, Identifiable {
    case any
    case battery
    case powerAdapter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any power source"
        case .battery: return "On battery"
        case .powerAdapter: return "Connected to power"
        }
    }
}

enum ProfileDisplayCondition: String, CaseIterable, Codable, Identifiable {
    case any
    case single
    case multiple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any display setup"
        case .single: return "One display"
        case .multiple: return "Multiple displays"
        }
    }
}

struct SmartProfileContext: Equatable {
    var activeApplicationBundleIdentifier: String?
    var hour: Int
    var isPluggedIn: Bool?
    var displayCount: Int
    var meetingIsActive: Bool
}

struct NotchProfileRules: Codable, Equatable {
    var applicationBundleIdentifiers: [String] = []
    var timeRangeEnabled = false
    var startHour = 9
    var endHour = 17
    var power: ProfilePowerCondition = .any
    var displays: ProfileDisplayCondition = .any
    var duringMeeting = false

    private var normalizedApplicationBundleIdentifiers: [String] {
        applicationBundleIdentifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    var hasConditions: Bool {
        !normalizedApplicationBundleIdentifiers.isEmpty
            || timeRangeEnabled
            || power != .any
            || displays != .any
            || duringMeeting
    }

    func matches(_ context: SmartProfileContext) -> Bool {
        guard hasConditions else { return false }

        if !normalizedApplicationBundleIdentifiers.isEmpty {
            guard let active = context.activeApplicationBundleIdentifier?.lowercased(),
                  normalizedApplicationBundleIdentifiers.contains(active) else { return false }
        }

        if timeRangeEnabled {
            let start = min(max(startHour, 0), 23)
            let end = min(max(endHour, 0), 23)
            let isInside = start == end
                || (start < end
                    ? (context.hour >= start && context.hour < end)
                    : (context.hour >= start || context.hour < end))
            guard isInside else { return false }
        }

        switch power {
        case .any:
            break
        case .battery:
            guard context.isPluggedIn == false else { return false }
        case .powerAdapter:
            guard context.isPluggedIn == true else { return false }
        }

        switch displays {
        case .any:
            break
        case .single:
            guard context.displayCount == 1 else { return false }
        case .multiple:
            guard context.displayCount > 1 else { return false }
        }

        if duringMeeting, !context.meetingIsActive { return false }
        return true
    }
}

struct NotchProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var systemImage: String
    var enabledTabs: [NotchTab]
    var widgetOrder: [NotchTab]
    var accent: Theme.Accent
    var panelStyle: Theme.PanelStyle
    var panelWidth: Double
    var rules: NotchProfileRules

    init(
        id: UUID = UUID(),
        name: String,
        systemImage: String = "circle.grid.2x2.fill",
        enabledTabs: [NotchTab] = [.home, .capture, .shortcuts, .music, .system],
        widgetOrder: [NotchTab] = NotchTab.allCases,
        accent: Theme.Accent = .graphite,
        panelStyle: Theme.PanelStyle = .gradient,
        panelWidth: Double = 520,
        rules: NotchProfileRules = NotchProfileRules()
    ) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.enabledTabs = enabledTabs
        self.widgetOrder = widgetOrder
        self.accent = accent
        self.panelStyle = panelStyle
        self.panelWidth = panelWidth
        self.rules = rules
    }

    var orderedTabs: [NotchTab] {
        let enabled = Set(enabledTabs).union([.home])
        var seen = Set<NotchTab>()
        var result = widgetOrder.filter { enabled.contains($0) && seen.insert($0).inserted }
        result += NotchTab.allCases.filter { enabled.contains($0) && seen.insert($0).inserted }
        return result
    }

    var displayName: String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Untitled Profile" : value
    }

    static let defaults: [NotchProfile] = [
        // Meeting stays first because a foreground work or media app may still
        // be active when a call begins, and the first matching profile wins.
        NotchProfile(
            id: UUID(uuidString: "99C206C1-D819-4DA3-97F4-87C8FDE7A102")!,
            name: "Meeting",
            systemImage: "video.fill",
            enabledTabs: [.home, .capture, .system, .activity],
            widgetOrder: [.home, .capture, .activity, .system],
            accent: .violet,
            panelWidth: 500,
            rules: NotchProfileRules(duringMeeting: true)
        ),
        NotchProfile(
            id: UUID(uuidString: "99C206C1-D819-4DA3-97F4-87C8FDE7A101")!,
            name: "Work",
            systemImage: "briefcase.fill",
            enabledTabs: [.home, .capture, .shortcuts, .system, .activity, .clipboard],
            widgetOrder: [.home, .capture, .shortcuts, .clipboard, .activity, .system],
            accent: .ocean,
            panelWidth: 540,
            rules: NotchProfileRules(applicationBundleIdentifiers: [
                "com.apple.dt.Xcode",
                "com.microsoft.VSCode",
                "com.openai.codex"
            ])
        ),
        NotchProfile(
            id: UUID(uuidString: "99C206C1-D819-4DA3-97F4-87C8FDE7A103")!,
            name: "Media",
            systemImage: "play.circle.fill",
            enabledTabs: [.home, .music, .system],
            widgetOrder: [.home, .music, .system],
            accent: .sunset,
            panelStyle: .tinted,
            panelWidth: 480,
            rules: NotchProfileRules(applicationBundleIdentifiers: [
                "com.apple.Music",
                "com.spotify.client",
                "com.apple.TV"
            ])
        ),
        NotchProfile(
            id: UUID(uuidString: "99C206C1-D819-4DA3-97F4-87C8FDE7A104")!,
            name: "Gaming",
            systemImage: "gamecontroller.fill",
            enabledTabs: [.home, .system],
            widgetOrder: [.home, .system],
            accent: .forest,
            panelStyle: .black,
            panelWidth: 460
        )
    ]
}
