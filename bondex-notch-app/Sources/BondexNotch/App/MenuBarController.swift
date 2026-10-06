import AppKit
import SwiftUI

/// The status item — the only chrome an LSUIElement app gets, so it carries
/// Settings, the panel toggle and Quit.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private let environment: AppEnvironment
    private let onOpenSettings: () -> Void
    private let onShowWelcome: () -> Void

    init(
        environment: AppEnvironment,
        onOpenSettings: @escaping () -> Void,
        onShowWelcome: @escaping () -> Void
    ) {
        self.environment = environment
        self.onOpenSettings = onOpenSettings
        self.onShowWelcome = onShowWelcome
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = BondexLogoMark.menuBarImage()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Rebuilt as it opens, from the state at that moment.
    ///
    /// It used to be rebuilt from Combine sinks on `$snapshot` and
    /// `$preferences`, which fire *before* the new value is stored — so the
    /// focus item always described the previous phase ("Start" while a timer
    /// ran, "Pause" once it was paused) and toggled widgets lagged a change.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        let toggle = NSMenuItem(
            title: environment.notch.state.isExpanded ? "Hide Notch Panel" : "Show Notch Panel",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let palette = NSMenuItem(
            title: "Command Palette…",
            action: #selector(openCommandPalette),
            keyEquivalent: ""
        )
        palette.target = self
        menu.addItem(palette)

        if environment.settings.isTabEnabled(.capture) {
            let capture = NSMenuItem(
                title: "Quick Capture…",
                action: #selector(openQuickCapture),
                keyEquivalent: ""
            )
            capture.target = self
            menu.addItem(capture)
        }

        if environment.settings.preferences.focusTimerEnabled {
            let focus = NSMenuItem(
                title: focusMenuTitle,
                action: #selector(toggleFocusTimer),
                keyEquivalent: ""
            )
            focus.target = self
            menu.addItem(focus)

            if environment.focusTimer.snapshot.isActive {
                let cancelFocus = NSMenuItem(
                    title: "Cancel Focus Timer",
                    action: #selector(cancelFocusTimer),
                    keyEquivalent: ""
                )
                cancelFocus.target = self
                menu.addItem(cancelFocus)
            }
        }

        menu.addItem(.separator())

        // An update a scheduled check found waits here instead of popping up
        // over whatever the person is doing.
        if let version = environment.updates.waitingVersion {
            let install = NSMenuItem(
                title: "Update to \(version)…",
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            )
            install.target = self
            install.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(install)
        } else if environment.updates.isConfigured {
            let check = NSMenuItem(
                title: "Check for Updates…",
                action: environment.updates.canCheck ? #selector(checkForUpdates) : nil,
                keyEquivalent: ""
            )
            check.target = self
            menu.addItem(check)
        }

        let feedback = NSMenuItem(
            title: "Send Feedback…",
            action: #selector(sendFeedback),
            keyEquivalent: ""
        )
        feedback.target = self
        menu.addItem(feedback)

        let welcome = NSMenuItem(
            title: "Welcome Tour…",
            action: #selector(showWelcome),
            keyEquivalent: ""
        )
        welcome.target = self
        menu.addItem(welcome)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Bondex Notch",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func checkForUpdates() {
        environment.updates.checkNow()
    }

    @objc private func sendFeedback() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let hasNotch = (NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) != nil) ? "Yes" : "No"
        let subject = "Bondex Notch Feedback (v\(version))".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = """
        [Describe your feedback, feature request, or issue here]

        ---
        App Version: \(version)
        macOS: \(osVersion)
        Hardware Notch: \(hasNotch)
        """.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:support@bondeth.site?subject=\(subject)&body=\(body)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func togglePanel() {
        environment.commandPalette.dismiss()
        environment.notch.toggle()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func showWelcome() {
        onShowWelcome()
    }

    @objc private func openCommandPalette() {
        environment.presentCommandPalette()
    }

    @objc private func openQuickCapture() {
        environment.quickCapture.begin()
        environment.notch.tab = .capture
        environment.notch.setPinned(true)
        environment.notch.expand()
        environment.requestKeyboardFocus?()
    }

    private var focusMenuTitle: String {
        let snapshot = environment.focusTimer.snapshot
        if snapshot.isRunning { return "Pause Focus Timer" }
        if snapshot.isActive { return "Resume Focus Timer" }
        return "Start \(environment.settings.preferences.defaultFocusMinutes)-Minute Focus"
    }

    @objc private func toggleFocusTimer() {
        let timer = environment.focusTimer
        if timer.snapshot.isRunning {
            timer.pause()
        } else if timer.snapshot.isActive {
            timer.resume()
        } else {
            timer.start(minutes: environment.settings.preferences.defaultFocusMinutes)
        }
    }

    @objc private func cancelFocusTimer() {
        environment.focusTimer.cancel()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
