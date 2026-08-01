import AppKit

/// AppKit lifecycle rather than a SwiftUI `App`: Bondex has no primary window,
/// and the notch panel needs NSPanel-level control that `WindowGroup` cannot
/// give.
///
/// An explicit `@main` type (instead of top-level code in `main.swift`) keeps
/// the entry point on the main actor, which everything it touches requires.
@main
struct BondexNotch {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if let flagIndex = arguments.firstIndex(of: "--render-previews") {
            let directory = arguments.count > flagIndex + 1
                ? arguments[flagIndex + 1]
                : FileManager.default.currentDirectoryPath
            exit(PreviewRenderer.run(outputDirectory: directory))
        }

        switch LiveActivityCommand.parse(arguments) {
        case .command(let command):
            exit(command.run())
        case .invalid(let flag, let message):
            FileHandle.standardError.write(Data("bondex: \(flag) \(message)\n".utf8))
            exit(2)
        case .none:
            break
        }

        // What an agent's hook actually runs. Writing the signal through the app
        // rather than asking users to `mkdir -p` and `touch` keeps the location
        // an implementation detail, and makes the hook a single line that cannot
        // be typo'd into a file the watcher never sees.
        switch AgentSignalCommand.parse(arguments) {
        case .command(let command):
            exit(command.run())
        case .invalid(let flag, let message):
            // Loudly, and without starting the app. A hook that names an agent
            // this build does not know is a configuration error the user has to
            // see — and falling through to `run()` below would answer it by
            // launching a duplicate panel on every tool call.
            FileHandle.standardError.write(Data("bondex: \(flag) \(message)\n".utf8))
            exit(2)
        case .none:
            break
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
