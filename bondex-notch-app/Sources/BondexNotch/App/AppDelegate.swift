import AppKit
import AppIntents
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var environment: AppEnvironment?
    private var windowController: NotchWindowController?
    private var menuBar: MenuBarController?
    private var settingsWindow: NSWindow?
    private var settingsHosting: NSHostingController<SettingsView>?
    private var welcomeWindow: NSWindow?

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

        let menuBar = MenuBarController(
            environment: environment,
            onOpenSettings: { [weak self] in self?.showSettings() },
            onShowWelcome: { [weak self] in self?.showWelcome() }
        )
        menuBar.install()
        self.menuBar = menuBar

        environment.start()
        BondexNotchShortcuts.updateAppShortcutParameters()
        if environment.needsOnboarding { showWelcome() }
        Log.app.info("Bondex Notch launched")
    }

    // MARK: Welcome

    private func showWelcome() {
        guard let environment else { return }
        if let welcomeWindow {
            welcomeWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(environment: environment) { [weak self] in
            self?.welcomeWindow?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "Welcome to Bondex Notch"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.06, blue: 0.075, alpha: 1)
        window.setContentSize(OnboardingView.size)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === welcomeWindow else { return }
        // Closed before the features page was confirmed: start with the
        // defaults rather than leave every permission-gated feature off, and
        // do not show the tour again — it is in the menu bar.
        if let environment, environment.needsOnboarding {
            environment.completeOnboarding(OnboardingChoices(preferences: environment.settings.preferences))
        }
        welcomeWindow = nil
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
        let requestedPage = page

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
        // Settings is designed dark. `.preferredColorScheme` covers the SwiftUI
        // views, but the AppKit pieces — text-field placeholders and caret,
        // menus, focus rings — take the window's appearance, which otherwise
        // follows a Light-mode system and draws them for a white window.
        window.appearance = NSAppearance(named: .darkAqua)
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
