import Foundation

/// The three sizes the panel can take.
enum NotchState: Equatable {
    /// Exactly the hardware notch. Invisible on a notched Mac.
    case collapsed
    /// A wider pill that reports one live thing (now playing, a download, a drop target).
    case peek
    /// The full widget surface.
    case expanded

    var isExpanded: Bool { self == .expanded }
}

/// What a peek is currently reporting, which is what decides how wide it is.
///
/// Separate cases rather than a `hasBanner` flag, because each needs genuinely
/// different room: artwork and an equaliser are small and fixed, live progress
/// needs readable text, a banner needs a line or two, and an agent strip grows
/// with every agent that starts working.
enum PeekContent: Equatable {
    /// A short-lived hardware control such as volume or display brightness.
    case systemHUD
    case media
    case live
    /// - Parameter agents: how many agents are working, each of which brings its
    ///   own mark and its own name.
    case agent(agents: Int)
    case banner
}

/// The values shown beside the notch when a hardware control changes.
struct SystemHUDPresentation: Equatable {
    enum Kind: Equatable {
        case volume
        case brightness
        case keyboardBrightness
        case battery
    }

    var kind: Kind
    var level: Double
    var isMuted = false
    var detail: String? = nil

    var clampedLevel: Double { min(max(level, 0), 1) }

    var percentage: Int { Int((clampedLevel * 100).rounded()) }
}

/// Which widget the expanded panel is showing.
enum NotchTab: String, CaseIterable, Codable, Identifiable {
    case home
    case music
    case system
    case live
    case files
    case activity
    case shelf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .music: return "Music"
        case .system: return "System"
        case .live: return "Live"
        case .files: return "Files"
        case .activity: return "Activity"
        case .shelf: return "Shelf"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .music: return "music.note"
        case .system: return "gauge.medium"
        case .live: return "waveform.path.ecg"
        case .files: return "arrow.down.circle.fill"
        case .activity: return "bell.fill"
        case .shelf: return "tray.full.fill"
        }
    }

    var requiredFeature: ProFeature? {
        switch self {
        case .files: return .fileActivity
        case .shelf: return .shelf
        default: return nil
        }
    }

    /// Fixed height for this tab's widget area, or nil to size to its content.
    ///
    /// The list tabs scroll inside a stable area: a panel that grew and shrank as
    /// items arrived and aged out would be far more distracting than one that
    /// stays put. Home, Music, and System are measured instead, so the panel is
    /// exactly as tall as what they show and does not reserve room for the
    /// tallest tab.
    var widgetHeight: CGFloat? {
        switch self {
        case .home, .music, .system: return nil
        case .live: return 148
        case .files, .activity, .shelf: return 148
        }
    }
}
