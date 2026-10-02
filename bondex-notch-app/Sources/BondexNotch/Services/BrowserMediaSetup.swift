import AppKit

/// Carries out a browser's `MediaApp.MediaAccessFix`, so letting Bondex see
/// web media is a button rather than a Terminal command.
@MainActor
enum BrowserMediaSetup {

    enum Outcome: Equatable {
        case done
        /// The browser was asked to quit and did not — usually a "quit with
        /// these tabs open?" prompt it is waiting on.
        case didNotQuit
        case couldNotOpen
    }

    /// How long a browser gets to quit before Bondex stops waiting. Long
    /// enough to save a session; short enough that a stuck prompt is reported
    /// rather than leaving the button spinning.
    static let quitTimeout: TimeInterval = 15

    /// Quits the browser politely — the same as ⌘Q, so it saves its windows
    /// and tabs — and opens it again with `arguments`.
    ///
    /// The arguments only reach a fresh launch: asking a browser that is
    /// already open to open "with" them just brings it forward, which is why
    /// running the command from Terminal appeared to do nothing while the
    /// browser was still open.
    static func relaunch(_ app: MediaApp, arguments: [String]) async -> Outcome {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
        guard let url = running.first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
        else { return .couldNotOpen }

        running.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(quitTimeout)
        while running.contains(where: { !$0.isTerminated }) {
            guard Date() < deadline else { return .didNotQuit }
            try? await Task.sleep(for: .milliseconds(200))
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return .done
        } catch {
            Log.music.error("Could not reopen \(app.displayName): \(error.localizedDescription)")
            return .couldNotOpen
        }
    }

    /// Brings the browser forward, so the menu the instructions name is the
    /// one in front of the user.
    static func bringToFront(_ app: MediaApp) {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
            .first?
            .activate()
    }
}
