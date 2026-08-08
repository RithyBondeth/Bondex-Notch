import AppKit
import Combine
import SwiftUI

/// The status item — the only chrome an LSUIElement app gets, so it carries
/// Settings, the panel toggle and Quit.
@MainActor
final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem?
    private let environment: AppEnvironment
    private let onOpenSettings: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment, onOpenSettings: @escaping () -> Void) {
        self.environment = environment
        self.onOpenSettings = onOpenSettings
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Bondex Notch"
        )
        item.button?.image?.isTemplate = true
        item.menu = makeMenu()
        statusItem = item

        environment.focusTimer.$snapshot
            .map(\.phase)
            .removeDuplicates()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: "Show Notch Panel",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        if environment.settings.preferences.quickCaptureEnabled {
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

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let tier = NSMenuItem(
            title: "Tier: \(environment.settings.tier.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        tier.isEnabled = false
        menu.addItem(tier)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Bondex Notch",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    /// The tier line is built once, so refresh it whenever the license changes.
    func refresh() {
        statusItem?.menu = makeMenu()
    }

    @objc private func togglePanel() {
        environment.notch.toggle()
    }

    @objc private func openSettings() {
        onOpenSettings()
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
