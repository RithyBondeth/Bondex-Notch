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
    case privacy
    case focus
    case meeting
    case media
    case live
    /// - Parameter agents: how many agents are working, each of which brings its
    ///   own mark and its own clock.
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
    case agents
    case capture
    case shortcuts
    case music
    case system
    case live
    case files
    case activity
    case clipboard
    case shelf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .agents: return "Agents"
        case .capture: return "Capture"
        case .shortcuts: return "Shortcuts"
        case .music: return "Music"
        case .system: return "System"
        case .live: return "Live"
        case .files: return "Files"
        case .activity: return "Activity"
        case .clipboard: return "Clipboard"
        case .shelf: return "Shelf"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .agents: return RobotGlyph.symbolName
        case .capture: return "square.and.pencil"
        case .shortcuts: return "bolt.square.fill"
        case .music: return "music.note"
        case .system: return "gauge.medium"
        case .live: return "waveform.path.ecg"
        case .files: return "arrow.down.circle.fill"
        case .activity: return "bell.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .shelf: return "tray.full.fill"
        }
    }

    /// The tallest this tab's widget area may grow, or nil for no cap.
    ///
    /// Every tab is as tall as its content, so the panel never reserves room for
    /// the tallest one. The list tabs stop at this height and scroll beyond it,
    /// so a long history cannot push the panel past its ceiling. They used to be
    /// held at exactly this height, on the theory that a list changing size as
    /// items arrived would be distracting — but items arrive while the panel is
    /// closed (you copy, download and capture in other apps), and the fixed
    /// height mostly showed two rows floating in a list-sized gap.
    var widgetHeight: CGFloat? {
        switch self {
        case .home, .agents, .music, .system: return nil
        case .capture, .shortcuts: return 132
        case .live: return 132
        case .files, .activity, .clipboard, .shelf: return 132
        }
    }
}
