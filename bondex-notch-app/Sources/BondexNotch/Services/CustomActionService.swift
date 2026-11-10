import AppKit
import Foundation

struct CustomActionFeedback: Equatable {
    let message: String
    let isError: Bool
}

/// Executes user-created actions without evaluating shell text.
/// Applications are opened through Launch Services, and Apple Shortcuts receives
/// the exact saved name as a Process argument rather than an interpolated command.
@MainActor
final class CustomActionService: ObservableObject {
    typealias ApplicationOpener = @MainActor (
        _ bundleIdentifier: String?, _ path: String
    ) -> Bool
    typealias ShortcutRunner = @MainActor (_ name: String) -> Bool

    @Published private(set) var feedback: CustomActionFeedback?

    private let openApplication: ApplicationOpener
    private let runShortcut: ShortcutRunner
    private var clearWorkItem: DispatchWorkItem?

    init(
        openApplication: @escaping ApplicationOpener = CustomActionService.openApplication,
        runShortcut: @escaping ShortcutRunner = CustomActionService.runShortcut
    ) {
        self.openApplication = openApplication
        self.runShortcut = runShortcut
    }

    func perform(
        _ action: CustomAction,
        toggleWidget: (NotchTab) -> Bool?
    ) {
        let result: CustomActionFeedback
        switch action.target {
        case let .application(bundleIdentifier, path):
            result = openApplication(bundleIdentifier, path)
                ? .init(message: "Opened \(action.title)", isError: false)
                : .init(message: "Couldn’t open \(action.title)", isError: true)

        case let .appleShortcut(name):
            result = runShortcut(name)
                ? .init(message: "Running \(action.title)", isError: false)
                : .init(message: "Couldn’t run \(action.title)", isError: true)

        case let .toggleWidget(tab):
            if let enabled = toggleWidget(tab) {
                result = .init(
                    message: "\(tab.title) \(enabled ? "enabled" : "disabled")",
                    isError: false
                )
            } else {
                result = .init(message: "\(tab.title) can’t be toggled", isError: true)
            }
        }
        show(result)
    }

    func seedFeedbackForPreview(_ feedback: CustomActionFeedback?) {
        clearWorkItem?.cancel()
        self.feedback = feedback
    }

    private func show(_ feedback: CustomActionFeedback) {
        clearWorkItem?.cancel()
        self.feedback = feedback
        let work = DispatchWorkItem { [weak self] in self?.feedback = nil }
        clearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    nonisolated static func shortcutArguments(for name: String) -> [String] {
        ["run", name]
    }

    private static func runShortcut(_ name: String) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = shortcutArguments(for: name)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private static func openApplication(
        bundleIdentifier: String?, path: String
    ) -> Bool {
        let workspace = NSWorkspace.shared
        if let bundleIdentifier,
           let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return workspace.open(url)
        }
        guard let url = fallbackApplicationURL(for: path) else { return false }
        return workspace.open(url)
    }

    /// Persisted preferences are not a trust boundary. Revalidate the picker
    /// result before using it as a fallback so a modified blob cannot turn an
    /// “open app” tile into an arbitrary document opener.
    nonisolated static func fallbackApplicationURL(for path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.pathExtension.lowercased() == "app", Bundle(url: url) != nil else {
            return nil
        }
        return url
    }
}
