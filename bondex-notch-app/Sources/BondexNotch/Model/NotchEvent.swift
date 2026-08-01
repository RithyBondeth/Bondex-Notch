import SwiftUI

/// Something worth surfacing in the notch.
///
/// Everything the activity feed shows originates here. macOS gives no public
/// way to read *other* apps' notifications, so this feed is built from what
/// Bondex observes itself: media changes, download progress, power state,
/// and shelf activity. See `NotificationService` for the full rationale.
struct NotchEvent: Identifiable, Equatable {
    enum Kind: String {
        case music
        case download
        case system
        case shelf
        case agent
        case live
        case app

        var systemImage: String {
            switch self {
            case .music: return "music.note"
            case .download: return "arrow.down.circle.fill"
            case .system: return "cpu"
            case .shelf: return "tray.full.fill"
            case .agent: return "sparkle"
            case .live: return "waveform.path.ecg"
            case .app: return "bell.fill"
            }
        }

        var tint: Color {
            switch self {
            case .music: return Color(red: 0.98, green: 0.33, blue: 0.45)
            case .download: return Color(red: 0.29, green: 0.62, blue: 0.98)
            case .system: return Color(red: 0.99, green: 0.72, blue: 0.25)
            case .shelf: return Color(red: 0.32, green: 0.80, blue: 0.55)
            case .agent: return Color(red: 0.85, green: 0.47, blue: 0.29)
            case .live: return Color(red: 0.62, green: 0.48, blue: 0.98)
            case .app: return Color(white: 0.75)
            }
        }

        /// Whether this is worth interrupting the notch with a transient banner.
        ///
        /// Everything here belongs in the activity feed; a banner is a stronger
        /// claim, reserved for things the user would otherwise have no sign of.
        /// Playback is the exception: the peek already reports it directly, with
        /// artwork and the equaliser, for as long as it lasts. Bannering it too
        /// would flash the track title over the menu bar for a few seconds on
        /// every change — putting back exactly the text the peek leaves out.
        /// Agent runs are the second exception, for the same reason as
        /// playback: the peek reported the work live, for as long as it lasted.
        /// A banner afterwards would be telling you about something you just
        /// spent ten minutes watching.
        var deservesBanner: Bool {
            switch self {
            case .music, .agent: return false
            case .download, .system, .shelf, .live, .app: return true
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let subtitle: String?
    let date: Date
    /// Which agent this is about, for `.agent` events.
    ///
    /// `Kind` alone is too coarse to draw with: it can say "an agent finished"
    /// but not *which*, so the row fell back to a generic symbol while the peek
    /// two seconds earlier had been showing the agent's actual mark. Carrying
    /// the agent lets the feed draw the same mark, and tint the row to match.
    let agent: AgentKind?

    init(
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        date: Date = Date(),
        agent: AgentKind? = nil
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.date = date
        self.agent = agent
    }

    /// The colour to draw this event in — the agent's own, when there is one.
    var tint: Color { agent?.tint ?? kind.tint }

    static func == (lhs: NotchEvent, rhs: NotchEvent) -> Bool { lhs.id == rhs.id }
}

/// Central, bounded event log. Services post, the feed widget observes.
@MainActor
final class EventCenter: ObservableObject {
    private static let capacity = 60

    @Published private(set) var events: [NotchEvent] = []
    /// Most recent event, used to drive the transient banner in the peek state.
    @Published private(set) var latest: NotchEvent?

    private var lastSignature: String?
    private var lastPostedAt: Date = .distantPast

    func post(_ event: NotchEvent) {
        // Collapse identical back-to-back events (a stalled download re-reporting
        // the same byte count should not spam the feed).
        let signature = "\(event.kind.rawValue)|\(event.title)|\(event.subtitle ?? "")"
        if signature == lastSignature, event.date.timeIntervalSince(lastPostedAt) < 2 {
            return
        }
        lastSignature = signature
        lastPostedAt = event.date

        events.insert(event, at: 0)
        if events.count > Self.capacity { events.removeLast(events.count - Self.capacity) }
        latest = event
    }

    func clear() {
        events.removeAll()
        latest = nil
        lastSignature = nil
    }
}
