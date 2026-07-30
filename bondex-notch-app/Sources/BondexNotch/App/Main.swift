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

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
