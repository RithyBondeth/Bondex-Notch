import AppKit

/// Watches the pointer globally so the panel reacts even though it never becomes
/// the active app.
///
/// SwiftUI's `.onHover` is unreliable inside a non-activating panel that spends
/// most of its life not key, so hover is driven from raw events instead. Global
/// *mouse* monitors need no accessibility permission (only keyboard ones do).
///
/// Events are coalesced before being delivered. A high-polling-rate mouse emits
/// well over a thousand `mouseMoved` events a second, and running the hover state
/// machine on every one of them competes with the panel's own animation for the
/// main thread.
@MainActor
final class MouseTracker {

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onMove: (CGPoint) -> Void

    /// Roughly one delivery per frame at 90Hz. Fine enough that a fast flick
    /// through the notch strip is never missed.
    private let minimumInterval: TimeInterval = 1.0 / 90.0
    private var lastDeliveredAt: TimeInterval = 0
    private var hasTrailingDelivery = false

    init(onMove: @escaping (CGPoint) -> Void) {
        self.onMove = onMove
    }

    func start() {
        guard globalMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            onMainActor { self?.pointerDidMove() }
        }

        // The global monitor stops firing once the pointer is over our own panel,
        // so a local monitor covers that case.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            onMainActor { self?.pointerDidMove() }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    // MARK: Coalescing

    private func pointerDidMove() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastDeliveredAt

        if elapsed >= minimumInterval {
            lastDeliveredAt = now
            onMove(NSEvent.mouseLocation)
            return
        }

        // Dropping the event outright would be wrong: if the pointer comes to
        // rest inside the notch on a dropped event, the panel would never see it
        // arrive. Schedule one trailing delivery instead, which re-reads the
        // pointer at fire time and so always reports where it ended up.
        guard !hasTrailingDelivery else { return }
        hasTrailingDelivery = true

        DispatchQueue.main.asyncAfter(deadline: .now() + (minimumInterval - elapsed)) { [weak self] in
            guard let self else { return }
            self.hasTrailingDelivery = false
            self.lastDeliveredAt = ProcessInfo.processInfo.systemUptime
            self.onMove(NSEvent.mouseLocation)
        }
    }
}
