import AppKit
import Foundation

/// One application Bondex can read playback out of.
///
/// Native players expose a scripting dictionary that reports the current track
/// directly. Browsers do not, so they are read through the page's own
/// `<video>`/`<audio>` element and `navigator.mediaSession` metadata — which is
/// what makes YouTube, YouTube Music, SoundCloud and friends visible.
struct MediaApp: Equatable, Hashable, Sendable, Identifiable {

    enum Engine: Equatable, Hashable, Sendable {
        /// Music.app's dictionary. `duration` is in seconds.
        case music
        /// Spotify's dictionary. Same shape, but `duration` is in milliseconds.
        case spotify
        /// Safari: `do JavaScript … in tab n of window m`.
        case webkit
        /// Chrome family: `execute javascript … in tab n of window m`.
        case chromium
        /// Dia: `execute tab n of window m javascript …`.
        case dia
    }

    let bundleIdentifier: String
    /// Name to address the app by in `tell application "…"`.
    let scriptName: String
    let displayName: String
    let engine: Engine

    /// Whether the user can actually turn on "Allow JavaScript from Apple
    /// Events". Chrome and Safari ship the switch off but offer it in a menu;
    /// some Chromium forks inherit the `execute javascript` command without
    /// exposing any way to permit it, and for those, telling the user to go and
    /// enable it would be sending them after a menu item that does not exist.
    var canEnableJavaScript = true

    /// Suffix a browser appends to a *window's* name while that window's active
    /// tab is playing audio. Where it exists it is a complete, JavaScript-free
    /// way to tell what is playing — title only, and only for the active tab, but
    /// far better than showing nothing.
    var audibleWindowMarker: String?

    var id: String { bundleIdentifier }

    var isBrowser: Bool {
        engine == .webkit || engine == .chromium || engine == .dia
    }

    /// True when the only way to read this browser is the window-title marker.
    var readsByWindowTitleOnly: Bool { !canEnableJavaScript && audibleWindowMarker != nil }

    var isRunning: Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .isEmpty
    }

    /// Where this browser hides the "Allow JavaScript from Apple Events" switch.
    /// It ships off, and it is the only manual step between Bondex and web media.
    ///
    /// Empty when there is nothing for the user to do — either because this is
    /// not a browser, or because the browser offers no way to allow it.
    var javaScriptHint: String {
        guard canEnableJavaScript else { return "" }
        switch engine {
        case .webkit:
            return """
            \(displayName) › Settings › Advanced › “Show features for web developers”,
            then Develop › Allow JavaScript from Apple Events.
            """
        case .chromium:
            return """
            \(displayName) › View › Developer ›
            Allow JavaScript from Apple Events.
            """
        case .dia:
            return """
            Quit Dia, then reopen it from Terminal with:
            open -a Dia --args --enable-applescript-javascript
            Dia requires this launch flag for JavaScript from Apple Events.
            """
        case .music, .spotify:
            return ""
        }
    }
}

extension MediaApp {

    // MARK: Native players

    static let music = MediaApp(
        bundleIdentifier: "com.apple.Music",
        scriptName: "Music",
        displayName: "Music",
        engine: .music
    )

    static let spotify = MediaApp(
        bundleIdentifier: "com.spotify.client",
        scriptName: "Spotify",
        displayName: "Spotify",
        engine: .spotify
    )

    // MARK: Browsers

    static let safari = MediaApp(
        bundleIdentifier: "com.apple.Safari",
        scriptName: "Safari",
        displayName: "Safari",
        engine: .webkit
    )

    static let chrome = MediaApp(
        bundleIdentifier: "com.google.Chrome",
        scriptName: "Google Chrome",
        displayName: "Chrome",
        engine: .chromium
    )

    static let brave = MediaApp(
        bundleIdentifier: "com.brave.Browser",
        scriptName: "Brave Browser",
        displayName: "Brave",
        engine: .chromium
    )

    static let edge = MediaApp(
        bundleIdentifier: "com.microsoft.edgemac",
        scriptName: "Microsoft Edge",
        displayName: "Edge",
        engine: .chromium
    )

    static let arc = MediaApp(
        bundleIdentifier: "company.thebrowser.Browser",
        scriptName: "Arc",
        displayName: "Arc",
        engine: .chromium
    )

    /// Dia exposes its tabs and a JavaScript command through AppleScript, but
    /// uses a different command grammar from both Arc and Chrome. It also keeps
    /// JavaScript execution disabled unless launched with the flag named in
    /// `javaScriptHint`.
    static let dia = MediaApp(
        bundleIdentifier: "company.thebrowser.dia",
        scriptName: "Dia",
        displayName: "Dia",
        engine: .dia
    )

    static let vivaldi = MediaApp(
        bundleIdentifier: "com.vivaldi.Vivaldi",
        scriptName: "Vivaldi",
        displayName: "Vivaldi",
        engine: .chromium
    )

    static let opera = MediaApp(
        bundleIdentifier: "com.operasoftware.Opera",
        scriptName: "Opera",
        displayName: "Opera",
        engine: .chromium
    )

    static let chromium = MediaApp(
        bundleIdentifier: "org.chromium.Chromium",
        scriptName: "Chromium",
        displayName: "Chromium",
        engine: .chromium
    )

    /// Atlas carries Chrome's dictionary, so `execute javascript` parses — but it
    /// always fails with `errAEEventNotPermitted` and there is no menu item or
    /// preference anywhere in the app to allow it. It does, however, put a speaker
    /// glyph on the window title while the active tab is audible, so that is how
    /// it gets read.
    static let atlas = MediaApp(
        bundleIdentifier: "com.openai.atlas",
        scriptName: "ChatGPT Atlas",
        displayName: "Atlas",
        engine: .chromium,
        canEnableJavaScript: false,
        audibleWindowMarker: "🔊"
    )

    /// Firefox is deliberately absent: it ships no scripting dictionary, so there
    /// is no supported way to read a tab's media state out of it.
    static let browsers: [MediaApp] = [
        .safari, .chrome, .brave, .edge, .arc, .dia, .atlas, .vivaldi, .opera, .chromium
    ]

    static let players: [MediaApp] = [.music, .spotify]

    static let all: [MediaApp] = players + browsers

    /// Running browsers, with the front-most one first so the window the user is
    /// actually looking at is probed before the ones behind it.
    ///
    /// Main actor because `NSWorkspace` traps when touched from anywhere else.
    /// Reading happens on a background queue, so the caller resolves this list
    /// first and hands it over.
    @MainActor
    static func runningBrowsers() -> [MediaApp] {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let running = browsers.filter(\.isRunning)
        guard let frontmost, let index = running.firstIndex(where: {
            $0.bundleIdentifier == frontmost
        }) else { return running }

        var ordered = running
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }

    @MainActor
    static func runningPlayers() -> [MediaApp] {
        players.filter(\.isRunning)
    }
}
