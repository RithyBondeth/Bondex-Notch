import AppKit

/// Watches the pointer globally so the panel reacts even though it never
/// becomes the active app.
///
/// SwiftUI's `.onHover` is unreliable inside a non-activating panel that spends
/// most of its life not key, so hover is driven from raw events instead. Global
/// *mouse* monitors need no accessibility permission (only keyboard ones do).
@MainActor
final class MouseTracker {

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onMove: (CGPoint) -> Void

    init(onMove: @escaping (CGPoint) -> Void) {
        self.onMove = onMove
    }

    func start() {
        guard globalMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.onMove(NSEvent.mouseLocation) }
        }

        // The global monitor stops firing once the pointer is over our own
        // panel, so a local monitor covers that case.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated { self.onMove(NSEvent.mouseLocation) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
