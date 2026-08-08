import AppKit
import EventKit
import Foundation

struct UpcomingMeeting: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let joinURL: URL?

    func startsSoon(at date: Date = Date()) -> Bool {
        let interval = startDate.timeIntervalSince(date)
        return endDate > date && interval <= 10 * 60 && interval >= -5 * 60
    }

    func isRelevantToHome(at date: Date = Date()) -> Bool {
        endDate > date && startDate.timeIntervalSince(date) <= 2 * 60 * 60
    }

    func relativeString(at date: Date = Date()) -> String {
        let seconds = Int(startDate.timeIntervalSince(date))
        if seconds <= 0 { return "Now" }
        if seconds < 60 { return "In <1 min" }
        return "In \(Int(ceil(Double(seconds) / 60))) min"
    }
}

/// Reads only the next time-bounded calendar event and keeps event details on
/// device. Calendar access is opt-in and the service is stopped entirely when
/// the meeting widget is disabled.
@MainActor
final class UpcomingMeetingService: ObservableObject {

    @Published private(set) var meeting: UpcomingMeeting?
    @Published private(set) var authorizationStatus: EKAuthorizationStatus =
        EKEventStore.authorizationStatus(for: .event)

    private let store = EKEventStore()
    private var timer: Timer?

    func start() {
        stop()
        refresh()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            onMainActor { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        meeting = nil
    }

    func requestAuthorization() {
        Task {
            do {
                _ = try await store.requestFullAccessToEvents()
            } catch {
                Log.app.error("Calendar authorization failed: \(error.localizedDescription)")
            }
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            refresh()
        }
    }

    func join(_ meeting: UpcomingMeeting) {
        guard let url = meeting.joinURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Deterministic data for the offscreen renderer; never called by the app.
    func seedForPreview(_ meeting: UpcomingMeeting?) {
        self.meeting = meeting
    }

    private func refresh() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard authorizationStatus == .fullAccess else {
            meeting = nil
            return
        }

        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-5 * 60),
            end: now.addingTimeInterval(24 * 60 * 60),
            calendars: nil
        )
        let event = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first

        meeting = event.map {
            UpcomingMeeting(
                id: $0.eventIdentifier ?? UUID().uuidString,
                title: $0.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty ?? "Untitled meeting",
                startDate: $0.startDate,
                endDate: $0.endDate,
                joinURL: Self.joinURL(for: $0)
            )
        }
    }

    /// Internal so meeting-link extraction can be verified without requesting
    /// access to the user's real calendar in tests.
    static func joinURL(for event: EKEvent) -> URL? {
        if let url = event.url, isWebURL(url) { return url }

        for text in [event.location, event.notes].compactMap({ $0 }) {
            guard let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue
            ) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let urls = detector.matches(in: text, range: range).compactMap(\.url)
            if let url = urls.first(where: isMeetingURL) { return url }
        }
        return nil
    }

    private static func isWebURL(_ url: URL) -> Bool {
        url.scheme == "https" || url.scheme == "http"
    }

    private static func isMeetingURL(_ url: URL) -> Bool {
        guard isWebURL(url), let host = url.host?.lowercased() else { return false }
        return ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com"]
            .contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
