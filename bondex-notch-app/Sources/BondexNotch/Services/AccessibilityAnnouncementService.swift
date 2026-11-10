import AppKit

/// Sends high-value state changes to VoiceOver without making the transient
/// notch itself focusable. Routine volume/brightness changes are deliberately
/// excluded because macOS already announces those system controls.
@MainActor
final class AccessibilityAnnouncementService {

    var isEnabled = true

    func announce(event: NotchEvent) {
        guard isEnabled, event.kind != .music else { return }
        let message = [event.title, event.subtitle]
            .compactMap { $0 }
            .joined(separator: ", ")
        announce(message)
    }

    func announce(_ message: String) {
        guard isEnabled, !message.isEmpty else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}
