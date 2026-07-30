import AppKit
import SwiftUI

/// The status item — the only chrome an LSUIElement app gets, so it carries
/// Settings, the panel toggle and Quit.
@MainActor
final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem?
    private let environment: AppEnvironment
    private let onOpenSettings: () -> Void

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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
