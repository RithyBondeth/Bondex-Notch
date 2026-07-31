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

/// Which widget the expanded panel is showing.
enum NotchTab: String, CaseIterable, Identifiable {
    case home
    case music
    case files
    case activity
    case shelf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .music: return "Music"
        case .files: return "Files"
        case .activity: return "Activity"
        case .shelf: return "Shelf"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .music: return "music.note"
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
    /// stays put. Home and Music are measured instead, so the panel is exactly as
    /// tall as what they are showing — which is why Home shrinks when nothing is
    /// playing, and why Music does not have to reserve room for the tallest tab.
    var widgetHeight: CGFloat? {
        switch self {
        case .home, .music: return nil
        case .files, .activity, .shelf: return 148
        }
    }
}
