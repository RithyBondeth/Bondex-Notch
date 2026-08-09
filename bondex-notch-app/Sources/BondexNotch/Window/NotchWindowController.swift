import AppKit
import Combine
import SwiftUI

/// Creates the panel, keeps it glued to the top of the active screen, and
/// routes pointer events into the view model.
@MainActor
final class NotchWindowController {

    private var panel: NotchPanel?
    private var hostingView: PassthroughHostingView<NotchRootView>?
    private var tracker: MouseTracker?
    private var cancellables = Set<AnyCancellable>()

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show(on screen: NSScreen) {
        environment.notch.updateGeometry(for: screen)

        let frame = environment.notch.geometry.windowFrame
        let panel = NotchPanel(contentRect: frame)

        let root = NotchRootView(environment: environment)
        let hosting = PassthroughHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        hosting.hitRegionProvider = { [weak self] in
            self?.environment.notch.hitRect ?? .zero
        }
        hosting.dropCatchRegionProvider = { [weak self] in
            guard let notch = self?.environment.notch, notch.isFileDragInFlight else {
                return .zero
            }
            return notch.geometry.dropCatchHitRect()
        }

        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hosting

        startTracking()
        observeScreenChanges()
    }

    func hide() {
        tracker?.stop()
        tracker = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        cancellables.removeAll()
    }

    // MARK: Pointer

    private func startTracking() {
        let tracker = MouseTracker { [weak self] location in
            self?.handlePointer(at: location)
        }
        tracker.start()
        self.tracker = tracker
    }

    private func handlePointer(at location: CGPoint) {
        // Only react to the pointer on the screen the panel lives on.
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        guard screen.frame.contains(location) || environment.notch.state.isExpanded else {
            return
        }
        environment.notch.pointerMoved(to: location)
    }

    // MARK: Screen changes

    /// Resolution changes, display arrangement changes and clamshell mode all
    /// move the notch, so the frame is re-derived whenever AppKit says the
    /// screen set changed.
    private func observeScreenChanges() {
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.repositionForCurrentScreen() }
            .store(in: &cancellables)
    }

    private func repositionForCurrentScreen() {
        guard let panel else { return }
        // The notch belongs to the built-in display; fall back to the main one
        // when it is closed or absent.
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
        guard let screen else { return }

        environment.notch.updateGeometry(for: screen)
        let frame = environment.notch.geometry.windowFrame
        panel.setFrame(frame, display: true)
        hostingView?.frame = CGRect(origin: .zero, size: frame.size)
        Log.window.debug("Repositioned notch panel to \(NSStringFromRect(frame), privacy: .public)")
    }
}
