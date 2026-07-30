import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var environment: AppEnvironment?
    private var windowController: NotchWindowController?
    private var menuBar: MenuBarController?
    private var settingsWindow: NSWindow?
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

        let windowController = NotchWindowController(environment: environment)
        windowController.show(on: screen)
        self.windowController = windowController

        let menuBar = MenuBarController(environment: environment) { [weak self] in
            self?.showSettings()
        }
        menuBar.install()
        self.menuBar = menuBar

        environment.settings.$preferences
            .map(\.licenseKey)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak menuBar] _ in menuBar?.refresh() }
            .store(in: &cancellables)

        environment.start()
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

    private func showSettings() {
        guard let environment else { return }

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(environment: environment)
        let hosting = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hosting)
        window.title = "Bondex Notch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 520))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }
}
