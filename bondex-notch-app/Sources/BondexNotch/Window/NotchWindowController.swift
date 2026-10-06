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
    private var outsideClickMonitor: Any?
    /// A pending move to the display the pointer went to, and which display.
    private var followWorkItem: DispatchWorkItem?
    private var followTargetID: CGDirectDisplayID?
    private var isMovingBetweenDisplays = false

    /// How long the pointer has to stay on another display before the notch
    /// follows it. Long enough that sweeping across a display on the way to a
    /// third, or nudging over the edge, does not drag the notch along.
    static let followDelay: TimeInterval = 0.45
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

        self.panel = panel
        self.hostingView = hosting

        startTracking()
        startKeyboardMonitoring()
        startOutsideClickMonitoring()
        observeKeyFocus()
        observeScreenChanges()
        // Through the same path as a display change, so a launch with only an
        // external display honours "Show synthetic notch on external displays"
        // instead of showing the panel regardless until the first change.
        repositionForCurrentScreen()
    }

    func hide() {
        tracker?.stop()
        tracker = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
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
        panel.makeKeyAndOrderFront(nil)
        // Do not install the hosting view as first responder here. The
        // Command Palette and Quick Capture use SwiftUI FocusState to select
        // their actual TextField on the next run-loop turn; making the hosting
        // view first responder afterwards steals that focus, especially when
        // the Settings window was previously key.
        DispatchQueue.main.async { [weak panel] in
            panel?.becomesKeyOnlyIfNeeded = true
        }
    }

    /// Gives keyboard focus back to whatever had it before the panel took it.
    ///
    /// A nonactivating panel that became key stays key after it collapses, so
    /// the next keystrokes — meant for the editor the user was in before Quick
    /// Capture or the palette — went to an invisible panel until they clicked
    /// back. (`resignKey()` does not do this; it only announces a change that
    /// has already happened.) Ordering the panel out lets the window server
    /// hand focus back to the active app; ordering it straight back in keeps
    /// the notch where it was, and on a collapsed notch there is nothing on
    /// screen to flicker.
    private func relinquishKeyFocus() {
        guard let panel, panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// Typing holds the panel open; losing focus — a click in another app —
    /// releases it. Collapsing returns focus to the app the user came from.
    private func observeKeyFocus() {
        guard let panel else { return }
        NotificationCenter.default
            .publisher(for: NSWindow.didBecomeKeyNotification, object: panel)
            .sink { [weak self] _ in self?.environment.notch.setHoldsOpenForKeyboard(true) }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { [weak self] _ in self?.environment.notch.setHoldsOpenForKeyboard(false) }
            .store(in: &cancellables)

        environment.notch.$state
            .removeDuplicates()
            .filter { !$0.isExpanded }
            .sink { [weak self] _ in
                // After the state change has been applied and the collapse
                // animation committed.
                DispatchQueue.main.async { self?.relinquishKeyFocus() }
            }
            .store(in: &cancellables)
    }

    /// A click anywhere outside Bondex closes the open panel.
    ///
    /// Without this a panel latched open by a click had no way to be dismissed
    /// short of finding its close button: clicking back into the app you were
    /// working in left it hanging over the screen. Global monitors only see
    /// events bound for *other* apps, so clicks on the panel itself, the menu
    /// bar item and Settings never arrive here. Mouse monitors need no
    /// accessibility permission.
    private func startOutsideClickMonitoring() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            onMainActor { self?.environment.notch.clickedOutside() }
        }
    }

    /// True while a text field in the panel is being edited — its field editor
    /// is first responder — so arrow keys belong to the caret.
    private var isEditingText: Bool {
        panel?.firstResponder is NSText
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
                // Collapsing also returns keyboard focus to the previous app.
                self.environment.notch.collapse()
                return nil
            case 123 where self.isEditingText, 124 where self.isEditingText:
                // Moving the caret in Quick Capture or a search field. Taking
                // these for tab switching made it impossible to edit a typo.
                return event
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
        if environment.settings.preferences.notchDisplay == .followPointer {
            follow(pointerAt: location)
        }
        // Only react to the pointer on the screen the panel lives on. With
        // AppKit's mouse rule, not `contains`: the top row of the screen — where
        // a pointer thrown at the notch comes to rest — has y equal to the
        // frame's maxY, and `contains` dropped every one of those events here.
        guard let panel, panel.isVisible, let screen = panel.screen ?? NSScreen.main else {
            return
        }
        guard NotchGeometry.pointer(location, isIn: screen.frame)
                || environment.notch.state.isExpanded else {
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

        // After the value is stored: `repositionForCurrentScreen` reads it back,
        // and reading it from `$preferences` (willSet) inverted the toggle.
        environment.settings.preferencesDidChange
            .map(\.notchDisplay)
            .removeDuplicates()
            .sink { [weak self] _ in self?.repositionForCurrentScreen() }
            .store(in: &cancellables)
    }

    /// Puts the panel on the display its setting calls for, or hides it.
    private func repositionForCurrentScreen() {
        guard let panel else { return }
        cancelFollow()
        let screens = NSScreen.screens
        let target = NotchPlacement.target(
            for: environment.settings.preferences.notchDisplay,
            among: screens.compactMap(NotchPlacement.Display.init),
            pointer: NSEvent.mouseLocation,
            main: NSScreen.main.flatMap(NotchPlacement.Display.init)
        )
        guard let target, let screen = screens.first(where: { $0.displayID == target.id }) else {
            panel.orderOut(nil)
            return
        }
        place(on: screen)
        panel.orderFrontRegardless()
    }

    private func place(on screen: NSScreen) {
        guard let panel else { return }
        environment.notch.updateGeometry(for: screen)
        let frame = environment.notch.geometry.windowFrame
        panel.setFrame(frame, display: true)
        hostingView?.frame = CGRect(origin: .zero, size: frame.size)
        Log.window.debug("Placed notch panel at \(NSStringFromRect(frame), privacy: .public)")
    }

    // MARK: Following the pointer

    /// Moves the notch to the display the pointer is on, once it has settled
    /// there — or at once when it is heading straight for the notch.
    private func follow(pointerAt location: CGPoint) {
        guard let panel, panel.isVisible, !isMovingBetweenDisplays,
              let current = panel.screen?.displayID,
              let screen = NSScreen.screens.first(where: {
                  NotchGeometry.pointer(location, isIn: $0.frame)
              }),
              let target = screen.displayID,
              target != current else {
            cancelFollow()
            return
        }
        // Never pull the panel out from under someone using it.
        guard canLeaveCurrentDisplay else {
            cancelFollow()
            return
        }

        // Pushed into the top centre of the other display: the notch is
        // wanted there now, not in half a second.
        let geometry = NotchGeometry.measure(screen: screen)
        if NotchGeometry.pointer(location, isIn: geometry.hoverRect(for: .collapsed)) {
            cancelFollow()
            move(to: screen)
            return
        }

        guard followTargetID != target else { return }
        cancelFollow()
        followTargetID = target
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.followWorkItem = nil
            self.followTargetID = nil
            let pointer = NSEvent.mouseLocation
            guard self.canLeaveCurrentDisplay,
                  let screen = NSScreen.screens.first(where: { $0.displayID == target }),
                  NotchGeometry.pointer(pointer, isIn: screen.frame) else { return }
            self.move(to: screen)
        }
        followWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.followDelay, execute: work)
    }

    private var canLeaveCurrentDisplay: Bool {
        !environment.notch.state.isExpanded && !environment.notch.isDropTargeted
    }

    private func cancelFollow() {
        followWorkItem?.cancel()
        followWorkItem = nil
        followTargetID = nil
    }

    /// A quick fade out and back in on the new display, so the notch is not
    /// seen to jump across the screen.
    private func move(to screen: NSScreen) {
        guard let panel, let target = screen.displayID else { return }
        isMovingBetweenDisplays = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            onMainActor {
                guard let self, let panel = self.panel else { return }
                // Looked up again: the display may have gone during the fade.
                if let screen = NSScreen.screens.first(where: { $0.displayID == target }) {
                    self.place(on: screen)
                }
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.16
                    panel.animator().alphaValue = 1
                }, completionHandler: { [weak self] in
                    onMainActor { self?.isMovingBetweenDisplays = false }
                })
            }
        })
    }
}
