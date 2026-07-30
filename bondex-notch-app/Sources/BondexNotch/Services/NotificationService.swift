import Foundation
import UserNotifications

/// Bridges Bondex's own notifications to and from Notification Center.
///
/// Deliberate limitation: macOS exposes no public API for reading *other*
/// applications' notifications — `UNUserNotificationCenter` is scoped to the
/// calling process, and the Notification Center database is SIP-protected. The
/// Activity widget is therefore a feed of what Bondex itself observes (media,
/// downloads, power, shelf) rather than a mirror of system notifications.
/// This class handles the part that *is* supported: posting Bondex alerts and
/// folding them back into the same feed.
@MainActor
final class NotificationService: NSObject, ObservableObject {

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let events: EventCenter

    /// `UNUserNotificationCenter.current()` raises `NSInternalInconsistencyException`
    /// when the process has no bundle proxy — which is the case for the bare
    /// SwiftPM executable and for the `--render-previews` tool. Resolving it
    /// lazily behind a bundle check keeps those paths working, and the rest of
    /// the class degrades to feed-only.
    private lazy var center: UNUserNotificationCenter? = {
        guard Bundle.main.bundleIdentifier != nil else {
            Log.app.notice("No bundle identifier; notification posting disabled")
            return nil
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }()

    init(events: EventCenter) {
        self.events = events
        super.init()
    }

    func start() {
        Task { await refreshStatus() }
    }

    func requestAuthorization() {
        guard let center else { return }
        Task {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                Log.app.error("Notification authorization failed: \(error.localizedDescription)")
            }
            await refreshStatus()
        }
    }

    private func refreshStatus() async {
        guard let center else { return }
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Post an alert *and* record it in the in-app feed, so the two never drift.
    func post(title: String, body: String, kind: NotchEvent.Kind = .app) {
        events.post(NotchEvent(kind: kind, title: title, subtitle: body))

        guard let center, authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Bondex is a background agent, so its own alerts should still appear
    /// while it is "frontmost".
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
