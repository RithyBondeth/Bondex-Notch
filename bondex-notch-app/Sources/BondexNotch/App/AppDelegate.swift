import AppKit
import AppIntents
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var environment: AppEnvironment?
    private var windowController: NotchWindowController?
    private var menuBar: MenuBarController?
    private var settingsWindow: NSWindow?
    private var settingsHosting: NSHostingController<SettingsView>?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon, no app menu.
        NSApp.setActivationPolicy(.accessory)

        // Prefer the display that actually has a notch.
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
        guard let screen else {
            Log.app.fault("No screen available at launch")
            return
        }

        let environment = AppEnvironment(screen: screen)
        self.environment = environment
        AppDependencyManager.shared.add(dependency: environment)
        environment.requestSettingsPage = { [weak self] page in
            self?.showSettings(page: page)
        }

        let windowController = NotchWindowController(environment: environment)
        windowController.show(on: screen)
        self.windowController = windowController

        let menuBar = MenuBarController(environment: environment) { [weak self] in
            self?.showSettings()
        }
        menuBar.install()
        self.menuBar = menuBar

        environment.settings.$preferences
            .removeDuplicates()
            .dropFirst()
            .sink { [weak menuBar] _ in menuBar?.refresh() }
            .store(in: &cancellables)

        environment.start()
        BondexNotchShortcuts.updateAppShortcutParameters()
        Log.app.info("Bondex Notch launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.stop()
        windowController?.hide()
    }

    /// The status item is the app's front door; clicking the Dock icon of a
    /// second launch should surface Settings rather than do nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: Settings

    private func showSettings(page: SettingsPage? = nil) {
        guard let environment else { return }
        let requestedPage: SettingsPage? = environment.settings.canUseApp ? page : .license

        if let settingsWindow {
            if let requestedPage {
                // Replacing only `rootView` with another SettingsView lets
                // SwiftUI preserve the existing view's @State, so commands
                // such as "Open Profiles settings" can leave the old page
                // selected. A fresh host gives the requested page a fresh
                // navigation state while all settings themselves remain
                // persisted in the shared environment.
                let hosting = NSHostingController(
                    rootView: SettingsView(environment: environment, initialPage: requestedPage)
                )
                settingsWindow.contentViewController = hosting
                settingsHosting = hosting
            }
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(environment: environment, initialPage: requestedPage ?? .general)
        let hosting = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hosting)
        window.title = "Bondex Notch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(
            calibratedRed: 0.055,
            green: 0.06,
            blue: 0.075,
            alpha: 0.98
        )
        window.isOpaque = false
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 800, height: 570))
        window.contentMinSize = NSSize(width: 720, height: 520)
        window.contentMaxSize = NSSize(width: 980, height: 760)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
        settingsHosting = hosting
    }
}
