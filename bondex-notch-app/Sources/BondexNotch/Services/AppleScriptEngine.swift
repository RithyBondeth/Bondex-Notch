import AppKit
import Foundation

/// Why an Apple Event did not produce a value.
enum ScriptFailure: Equatable, Sendable {
    /// Automation for the target app has not been granted, or was denied.
    case automationDenied
    /// The target app refuses to run JavaScript sent over Apple Events. Browsers
    /// ship with this off; it is a one-time toggle in the app's own menus.
    case javaScriptDisabled
    /// The app quit mid-script, the tab went away, or the dictionary does not
    /// have what we asked for. Not worth reporting to the user.
    case transient
}

struct ScriptOutcome: Sendable {
    var value: String?
    var failure: ScriptFailure?

    var isDenied: Bool { failure == .automationDenied }
    var isJavaScriptDisabled: Bool { failure == .javaScriptDisabled }
}

/// Serialises every Apple Event through one lock.
///
/// `NSAppleScript` is not safe to use from several threads at once, and a
/// blocked event can take seconds to time out, so all media reads share this
/// one engine and take turns.
final class AppleScriptEngine: @unchecked Sendable {

    /// Recursive so a caller can hold the lock across a group of related events
    /// (one browser scan, say) without deadlocking on each individual one.
    private let lock = NSRecursiveLock()

    func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: Execution

    func run(_ source: String) -> ScriptOutcome {
        execute(source, isJavaScript: false)
    }

    /// Runs a script whose payload is `execute javascript` / `do JavaScript`.
    ///
    /// Kept separate because the failure that matters here — the browser refusing
    /// to run JavaScript sent over Apple Events — is only identifiable in context.
    /// Chrome says so in the message, but Chromium browsers generally just fail to
    /// resolve the tab specifier at all and report `errAEEventNotPermitted`, which
    /// is indistinguishable from any other refusal unless you know you were asking
    /// for JavaScript.
    func runJavaScript(_ source: String) -> ScriptOutcome {
        execute(source, isJavaScript: true)
    }

    private func execute(_ source: String, isJavaScript: Bool) -> ScriptOutcome {
        lock.lock()
        defer { lock.unlock() }

        guard let script = NSAppleScript(source: source) else {
            return ScriptOutcome(value: nil, failure: .transient)
        }

        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)

        if let error {
            return ScriptOutcome(
                value: nil,
                failure: Self.classify(error, isJavaScript: isJavaScript)
            )
        }
        return ScriptOutcome(value: descriptor.stringValue, failure: nil)
    }

    /// Raw bytes rather than a string, for Music.app's artwork.
    func runForData(_ source: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        let data = descriptor.data
        return data.isEmpty ? nil : data
    }

    // MARK: Errors

    /// `errAEEventNotPermitted`. A browser with JavaScript-over-Apple-Events
    /// switched off reports this for *every* evaluation, valid tab or not.
    private static let notPermitted = -1723
    /// `errAEIllegalIndex` and `errAENoSuchObject`: the tab or window is gone.
    private static let staleReferenceCodes = [-1719, -1728]
    /// The target app quit mid-script.
    private static let appQuitCodes = [-600, -609]

    private static func classify(_ error: NSDictionary, isJavaScript: Bool) -> ScriptFailure {
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        let message = (error[NSAppleScript.errorMessage] as? String ?? "").lowercased()

        // -1743 is the documented "user declined Automation" code.
        if code == -1743 { return .automationDenied }

        // Chrome states the reason outright; most other Chromium browsers do not,
        // so a refusal on a script we know was JavaScript means the toggle is off.
        if message.contains("javascript") { return .javaScriptDisabled }
        if isJavaScript, code == notPermitted { return .javaScriptDisabled }

        if !staleReferenceCodes.contains(code),
           !appQuitCodes.contains(code),
           code != 0 {
            Log.music.debug("AppleScript error \(code): \(message, privacy: .public)")
        }
        return .transient
    }
}

// MARK: - String escaping

extension String {
    /// Escapes this string for use as an AppleScript string literal.
    var appleScriptLiteral: String {
        let escaped = replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
