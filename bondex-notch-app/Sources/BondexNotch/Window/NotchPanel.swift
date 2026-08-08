import AppKit
import SwiftUI

/// The floating panel that hangs off the top edge of the display.
///
/// It is deliberately *not* activating: clicking a control in the notch must
/// never steal focus from whatever the user is typing in.
final class NotchPanel: NSPanel {

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Above the menu bar, so the panel can overlap the notch itself.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // The SwiftUI layer draws its own shadow.
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true

        // Keep the panel out of screenshots of "windows" and out of Exposé.
        isExcludedFromWindowsMenu = true
        becomesKeyOnlyIfNeeded = true
    }

    /// Needed so Quick Capture, search, and settings text fields can receive
    /// keystrokes when the panel is used interactively.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that only accepts clicks inside the panel's currently visible
/// shape.
///
/// The window is fixed at its largest footprint so the SwiftUI spring can run
/// unimpeded, which means most of the window is transparent. Without this,
/// that transparent area would swallow clicks meant for the app underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {

    /// Interactive region in this view's coordinate space. Supplied by the
    /// controller and re-read on every hit test, so it always matches state.
    var hitRegionProvider: () -> CGRect = { .zero }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitRegionProvider().contains(point) else { return nil }
        return super.hitTest(point)
    }
}
