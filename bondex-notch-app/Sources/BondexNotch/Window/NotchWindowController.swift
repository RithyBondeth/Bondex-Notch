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
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        environment.requestKeyboardFocus = { [weak self] in
            self?.focusPanel()
            // The palette/composer is inserted by the same published state
            // change that requested focus. Repeat on the next run-loop turn so
            // its TextField exists before SwiftUI resolves @FocusState.
            DispatchQueue.main.async { self?.focusPanel() }
        }
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

        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hosting

        startTracking()
        startKeyboardMonitoring()
        observeScreenChanges()
    }

    func hide() {
        tracker?.stop()
        tracker = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        cancellables.removeAll()
    }

    // MARK: Pointer

    private func focusPanel() {
        guard let panel else { return }
        // A nonactivating panel normally avoids stealing keyboard input. A
        // global shortcut is an explicit request to type here, so temporarily
        // allow it to become key without activating Bondex as a whole.
        panel.becomesKeyOnlyIfNeeded = false
        panel.orderFrontRegardless()
        panel.makeKey()
        if let hostingView { panel.makeFirstResponder(hostingView) }
        DispatchQueue.main.async { [weak panel] in
            panel?.becomesKeyOnlyIfNeeded = true
        }
    }

    private func startKeyboardMonitoring() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.panel?.isKeyWindow == true,
                  self.environment.notch.state.isExpanded else { return event }

            if self.environment.commandPalette.isPresented {
                switch event.keyCode {
                case 53: // Escape
                    self.environment.commandPalette.dismiss()
                    return nil
                case 125: // Down arrow
                    self.environment.commandPalette.moveSelection(
                        by: 1,
                        resultCount: self.environment.commandPaletteResults.count
                    )
                    return nil
                case 126: // Up arrow
                    self.environment.commandPalette.moveSelection(
                        by: -1,
                        resultCount: self.environment.commandPaletteResults.count
                    )
                    return nil
                case 36, 76: // Return or keypad Enter
                    self.environment.executeSelectedCommand()
                    return nil
                default:
                    return event
                }
            }

            switch event.keyCode {
            case 53: // Escape
                if self.environment.notch.tab == .capture {
                    self.environment.quickCapture.cancelDraft()
                }
                self.environment.notch.collapse()
                self.panel?.resignKey()
                return nil
            case 123: // Left arrow
                self.selectAdjacentTab(offset: -1)
                return nil
            case 124: // Right arrow
                self.selectAdjacentTab(offset: 1)
                return nil
            default:
                return event
            }
        }
    }

    private func selectAdjacentTab(offset: Int) {
        let tabs = environment.availableTabs
        guard let current = tabs.firstIndex(of: environment.notch.tab), !tabs.isEmpty else {
            return
        }
        let destination = (current + offset + tabs.count) % tabs.count
        withAnimation(Motion.content(environment.settings.motion)) {
            environment.notch.tab = tabs[destination]
        }
    }

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
