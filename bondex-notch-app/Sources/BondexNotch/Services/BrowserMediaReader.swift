import Foundation

/// Reads playback out of a browser tab.
///
/// Browsers publish no now-playing information over their scripting
/// dictionaries, but they can be asked to evaluate JavaScript in a tab. The page
/// itself knows everything worth knowing: the `<video>`/`<audio>` element has
/// duration, position and paused state, and `navigator.mediaSession.metadata` —
/// which YouTube, YouTube Music, SoundCloud, Spotify Web, Twitch and most other
/// players populate — carries the title, artist and artwork.
///
/// The one cost is a toggle the user has to flip once per browser
/// ("Allow JavaScript from Apple Events"); `ScriptFailure.javaScriptDisabled`
/// reports when that is still off so the UI can say so instead of silently
/// showing nothing.
///
/// Not `@MainActor`: every method runs inside `AppleScriptEngine`'s lock on a
/// background queue.
final class BrowserMediaReader: @unchecked Sendable {

    struct Reading {
        var track: NowPlaying?
        var failure: ScriptFailure?
        /// Which app produced `failure`, so the UI can name the browser the user
        /// needs to change a setting in.
        var failedApp: MediaApp?
    }

    enum Transport {
        case playPause, next, previous
    }

    /// A tab, addressed the way AppleScript addresses it. Indices shift when the
    /// user reorders or closes tabs, so `host` is carried along to notice.
    private struct TabRef: Equatable {
        var app: MediaApp
        var window: Int
        var tab: Int
        var host: String
    }

    private let engine: AppleScriptEngine
    /// The tab media was last found in, probed directly on the next tick so the
    /// common case costs one Apple Event rather than a full scan.
    private var pinned: TabRef?
    private var lastScanAt: Date?

    /// How often to sweep every open tab when nothing is pinned. A scan touches
    /// every window of every running browser, so it must not run at tick rate.
    private let scanInterval: TimeInterval = 3.0
    /// Upper bound on JavaScript evaluations per scan.
    private let probeLimit = 6

    init(engine: AppleScriptEngine) {
        self.engine = engine
    }

    func reset() {
        pinned = nil
        lastScanAt = nil
    }

    // MARK: Reading

    /// - Parameter apps: running browsers, best candidate first. Resolved by the
    ///   caller on the main actor, because asking AppKit what is running is not
    ///   safe from the queue this runs on.
    func read(in apps: [MediaApp]) -> Reading {
        /// First failure seen this pass. A denial or a browser with JavaScript
        /// turned off is worth reporting even though the scan carries on.
        var failure: ScriptFailure?
        var failedApp: MediaApp?

        func record(_ next: ScriptFailure?, from app: MediaApp) {
            guard failure == nil, let next, next != .transient else { return }
            failure = next
            failedApp = app
        }

        // Fast path: the tab media was in last time is usually still the one.
        if let pinned {
            let outcome = probe(pinned)
            if outcome.track != nil { return outcome }
            record(outcome.failure, from: pinned.app)
            if failure != nil {
                return Reading(track: nil, failure: failure, failedApp: failedApp)
            }
            self.pinned = nil
        }

        let scriptable = apps.filter { !$0.readsByWindowTitleOnly }
        let titleOnly = apps.filter(\.readsByWindowTitleOnly)

        // Sweeping every tab means evaluating JavaScript in up to `probeLimit` of
        // them, so it is rate-limited. When a sweep is due it goes first, because
        // it yields artwork, position and working transport controls.
        if lastScanAt == nil || Date().timeIntervalSince(lastScanAt!) >= scanInterval {
            lastScanAt = Date()

            for app in scriptable {
                let candidates = locateCandidates(in: app)
                record(candidates.failure, from: app)

                var best: NowPlaying?
                for reference in candidates.tabs.prefix(probeLimit) {
                    let outcome = probe(reference)
                    record(outcome.failure, from: app)
                    guard let track = outcome.track else { continue }

                    if track.isPlaying {
                        pinned = reference
                        return Reading(track: track)
                    }
                    // Remember a paused tab, but keep looking for a playing one.
                    if best == nil {
                        best = track
                        pinned = reference
                    }
                }

                if let best { return Reading(track: best) }
            }
        }

        // Title-only browsers are read on *every* tick, not just when a sweep is
        // due: the read is a single Apple Event with no JavaScript, and there is
        // no tab to pin, so rate-limiting it would report "nothing playing" on the
        // ticks in between — the track would blink out of the notch once a second.
        for app in titleOnly {
            if let track = readAudibleWindowTitle(in: app) {
                return Reading(track: track)
            }
        }

        return Reading(track: nil, failure: failure, failedApp: failedApp)
    }

    // MARK: Transport

    /// Returns true when the browser accepted the command.
    func perform(_ transport: Transport, on app: MediaApp) -> Bool {
        guard let reference = pinned, reference.app == app else { return false }
        let outcome = engine.runJavaScript(wrap(script(for: transport), for: reference))
        return outcome.value?.isEmpty == false
    }

    // MARK: Locating

    private struct Candidates {
        var tabs: [TabRef] = []
        var failure: ScriptFailure?
    }

    /// Lists tabs worth evaluating JavaScript in, best bet first.
    ///
    /// A known media host is a far stronger signal than "this tab is frontmost in
    /// some window", and browsers routinely have more windows than `probeLimit` —
    /// a browser with nine small side windows open would otherwise use up the
    /// whole budget on them and never reach the tab actually playing.
    private func locateCandidates(in app: MediaApp) -> Candidates {
        let outcome = engine.run(tabListScript(for: app))
        guard let raw = outcome.value else {
            return Candidates(tabs: [], failure: outcome.failure)
        }

        var activeMedia: [TabRef] = []
        var backgroundMedia: [TabRef] = []
        var activeOther: [TabRef] = []

        for window in Self.parseWindows(raw) {
            for (offset, url) in window.urls.enumerated() {
                guard let host = URL(string: url)?.host else { continue }

                let tab = offset + 1
                let reference = TabRef(app: app, window: window.index, tab: tab, host: host)
                let isActive = tab == window.activeTab

                switch (Self.isKnownMediaHost(host), isActive) {
                case (true, true): activeMedia.append(reference)
                case (true, false): backgroundMedia.append(reference)
                case (false, true): activeOther.append(reference)
                case (false, false): break
                }
            }
        }

        return Candidates(
            tabs: activeMedia + backgroundMedia + activeOther,
            failure: outcome.failure
        )
    }

    /// Hosts probed even when their tab is in the background. The active tab is
    /// always probed, so this list only needs to cover "playing in a tab I am
    /// not looking at" — the case that matters for music.
    static func isKnownMediaHost(_ host: String) -> Bool {
        let needles = [
            "youtube.com", "youtu.be", "soundcloud.com", "spotify.com",
            "music.apple.com", "podcasts.apple.com", "twitch.tv", "vimeo.com",
            "bandcamp.com", "mixcloud.com", "deezer.com", "tidal.com",
            "pandora.com", "audiomack.com", "netflix.com", "primevideo.com",
            "disneyplus.com", "hbomax.com", "max.com", "crunchyroll.com",
            "dailymotion.com", "bilibili.com", "nicovideo.jp", "plex.tv",
            "jellyfin.org", "last.fm", "napster.com", "qobuz.com"
        ]
        return needles.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    // MARK: Window-title fallback

    /// Reads the one thing a browser will tell us without running JavaScript:
    /// which *window* is making noise.
    ///
    /// The marker is reliable — it is on the window if and only if audio is coming
    /// out of it — but it does not say which tab, and a window's name is always
    /// its **active** tab's. Taking the name at face value reports whatever the
    /// user happens to be looking at: with a video playing in tab 3 and a PDF tool
    /// focused in tab 4, the window is named for the PDF tool and carries the
    /// marker, so the naive read claims the PDF tool is playing.
    ///
    /// So the audible tab is identified rather than assumed: the active tab if it
    /// is on a media host, otherwise the sole media-host tab in that window. If
    /// neither is true the window is skipped, because a wrong title is worse than
    /// no title.
    ///
    /// What comes back is a title and nothing else — no position, no artwork, and
    /// no way to drive playback, since there is no handle on the media element.
    private func readAudibleWindowTitle(in app: MediaApp) -> NowPlaying? {
        guard let marker = app.audibleWindowMarker else { return nil }
        guard let raw = engine.run(audibleWindowScript(for: app, marker: marker)).value else {
            return nil
        }

        for window in Self.parseWindows(raw) {
            // A tab's title must line up with its URL, or the wrong one gets named.
            guard window.urls.count == window.titles.count else { continue }

            let tabs = zip(window.urls, window.titles).enumerated().compactMap {
                index, pair -> (isActive: Bool, host: String, title: String)? in
                guard let host = URL(string: pair.0)?.host else { return nil }
                return (index + 1 == window.activeTab, host, pair.1)
            }

            let mediaTabs = tabs.filter { Self.isKnownMediaHost($0.host) }
            // The active tab if it is a media site; otherwise the window's one and
            // only media tab. With two candidates there is no way to tell which is
            // making the noise, and a confidently wrong title is worse than none.
            guard let audible = mediaTabs.first(where: \.isActive)
                    ?? (mediaTabs.count == 1 ? mediaTabs.first : nil) else { continue }

            let title = Self.strippedTitle(audible.title.replacingOccurrences(of: marker, with: ""))
            guard !title.isEmpty else { continue }

            return NowPlaying(
                source: app,
                title: title,
                artist: "",
                album: "",
                // The marker means audio is coming out right now. There is no
                // paused state to report — a paused tab simply loses the marker.
                isPlaying: true,
                duration: 0,
                position: 0,
                artwork: nil,
                artworkURL: nil,
                supportsTransport: false
            )
        }
        return nil
    }

    /// One window's tabs, as returned by a bulk query.
    private struct WindowInventory {
        var index: Int
        var activeTab: Int
        var urls: [String]
        var titles: [String]
    }

    /// The audible window's tabs, fetched a whole list at a time.
    ///
    /// Asking for each tab's URL and title individually is what a first cut looks
    /// like, and on a browser with a few windows open it measured **1.1 seconds
    /// per call** — every property of every tab is its own Apple Event round trip,
    /// and this runs once a second. `URL of every tab of window n` returns the
    /// whole list in a single event; combined with only descending into windows
    /// that carry the marker, the same read costs ~185ms, and when nothing is
    /// playing it is a single `name of every window`.
    private func audibleWindowScript(for app: MediaApp, marker: String) -> String {
        """
        tell application "\(app.scriptName)"
            set sep to (character id 1)
            set AppleScript's text item delimiters to sep
            set out to ""
            set windowNames to name of every window
            set wi to 0
            repeat with windowName in windowNames
                set wi to wi + 1
                if (windowName as text) contains \(marker.appleScriptLiteral) then
                    try
                        set out to out & "U" & sep & wi & sep & ¬
                            ((URL of every tab of window wi) as text) & linefeed
                        set out to out & "N" & sep & wi & sep & ¬
                            ((title of every tab of window wi) as text) & linefeed
                        set out to out & "A" & sep & wi & sep & ¬
                            (active tab index of window wi) & linefeed
                    end try
                end if
            end repeat
            return out
        end tell
        """
    }

    /// Parses the `U`/`N`/`A` line triples the bulk scripts emit. Lists are joined
    /// with the same control character that separates the fields, which is
    /// unambiguous because no URL or page title can contain it.
    private static func parseWindows(_ raw: String) -> [WindowInventory] {
        var byIndex: [Int: WindowInventory] = [:]

        for line in raw.components(separatedBy: .newlines) {
            let fields = line.components(separatedBy: separator)
            guard fields.count >= 3, let window = Int(fields[1]) else { continue }
            let values = Array(fields.dropFirst(2))

            var inventory = byIndex[window]
                ?? WindowInventory(index: window, activeTab: 0, urls: [], titles: [])
            switch fields[0] {
            case "U": inventory.urls = values
            case "N": inventory.titles = values
            case "A": inventory.activeTab = Int(values[0]) ?? 0
            default: continue
            }
            byIndex[window] = inventory
        }

        // Titles are only requested by the window-title path; the tab-listing
        // script omits them, so their absence is not a parse failure.
        return byIndex.values
            .filter { !$0.urls.isEmpty }
            .sorted { $0.index < $1.index }
    }

    // MARK: Probing

    private func probe(_ reference: TabRef) -> Reading {
        let outcome = engine.runJavaScript(wrap(Self.readScript, for: reference))
        guard let raw = outcome.value, !raw.isEmpty else {
            return Reading(track: nil, failure: outcome.failure)
        }

        let fields = raw.components(separatedBy: Self.separator)
        guard fields.count >= 9, fields[0] == "OK" else {
            return Reading(track: nil, failure: nil)
        }

        // The tab indices may have shifted under us; a different host means the
        // pin is stale even though *something* is playing there.
        guard fields[8] == reference.host else {
            return Reading(track: nil, failure: nil)
        }

        let rawDuration = Double(fields[4]) ?? 0
        // Live streams report an infinite duration. Zero reads as "unknown" and
        // the progress bar hides itself.
        let duration = rawDuration.isFinite ? rawDuration : 0

        let track = NowPlaying(
            source: reference.app,
            title: Self.strippedTitle(fields[1]),
            artist: fields[2],
            album: fields[3],
            isPlaying: fields[6] == "y",
            duration: duration,
            position: Double(fields[5]) ?? 0,
            artwork: nil,
            artworkURL: fields[7].isEmpty ? nil : URL(string: fields[7])
        )
        return Reading(track: track, failure: nil)
    }

    /// Pages that do not set `mediaSession` fall back to `document.title`, which
    /// carries the site's own suffix and an unread-count prefix.
    static func strippedTitle(_ title: String) -> String {
        // Trim first and between every step. The window-title path removes the
        // audible marker before calling this, which leaves a trailing space — and
        // a suffix check against an untrimmed string silently matches nothing.
        var value = title.trimmingCharacters(in: .whitespaces)

        // "(3) Some Video - YouTube" → "Some Video - YouTube".
        if value.hasPrefix("("), let close = value.firstIndex(of: ")") {
            let counter = value[value.index(after: value.startIndex)..<close]
            if !counter.isEmpty, counter.allSatisfy(\.isNumber) {
                value = String(value[value.index(after: close)...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        for suffix in [" - YouTube", " | Spotify", " - Twitch", " on Vimeo"] {
            if value.hasSuffix(suffix) {
                value = String(value.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return value
    }

    // MARK: Scripts

    /// Field separator for the JavaScript payload's return value. Chosen so it
    /// cannot collide with anything in a track title.
    static let separator = "\u{01}"

    private func wrap(_ javaScript: String, for reference: TabRef) -> String {
        let literal = javaScript.appleScriptLiteral
        switch reference.app.engine {
        case .chromium:
            return """
            tell application "\(reference.app.scriptName)" to execute javascript \
            \(literal) in tab \(reference.tab) of window \(reference.window)
            """
        case .webkit:
            return """
            tell application "\(reference.app.scriptName)" to do JavaScript \
            \(literal) in tab \(reference.tab) of window \(reference.window)
            """
        case .music, .spotify:
            return ""
        }
    }

    /// Every window's tab URLs plus which tab is frontmost.
    ///
    /// Deliberately free of JavaScript, so it works before the user has enabled
    /// the toggle. Tabs are fetched a list at a time rather than one property at a
    /// time, for the reason spelled out on `audibleWindowScript`.
    private func tabListScript(for app: MediaApp) -> String {
        let activeIndex = app.engine == .chromium
            ? "active tab index of window wi"
            : "index of current tab of window wi"

        return """
        tell application "\(app.scriptName)"
            set sep to (character id 1)
            set AppleScript's text item delimiters to sep
            set out to ""
            set windowCount to count of windows
            repeat with wi from 1 to windowCount
                try
                    set out to out & "U" & sep & wi & sep & ¬
                        ((URL of every tab of window wi) as text) & linefeed
                    set out to out & "A" & sep & wi & sep & \(activeIndex) & linefeed
                end try
            end repeat
            return out
        end tell
        """
    }

    /// Picks the media element the user most likely cares about: playing beats
    /// paused, audible beats muted, and longer beats shorter. Anything under
    /// three seconds is a UI sound effect, not content.
    ///
    /// Written without double quotes or backslashes so it survives being
    /// embedded in an AppleScript string literal unchanged.
    static let findElement = """
    var L=document.querySelectorAll('video,audio');var b=null;var bs=-1;\
    for(var i=0;i<L.length;i++){var e=L[i];var d=e.duration;\
    if(!d||d!==d||d<3)continue;var s=(e.paused?0:2)+(e.muted?0:1);\
    if(s>bs||(s===bs&&d>b.duration)){b=e;bs=s}}
    """

    static let readScript = """
    (function(){var S=String.fromCharCode(1);\(findElement)if(!b)return '';\
    var m=null;try{m=navigator.mediaSession.metadata}catch(x){}\
    var a='';if(m&&m.artwork){var w=-1;for(var j=0;j<m.artwork.length;j++){\
    var g=m.artwork[j];var p=parseInt((g.sizes||'').split('x')[0],10);\
    if(!p||p!==p){p=0}if(p>w){w=p;a=g.src||''}}}\
    var t=(m&&m.title)||document.title||'';var r=(m&&m.artist)||'';\
    var al=(m&&m.album)||'';\
    return ['OK',t,r,al,b.duration,b.currentTime,b.paused?'n':'y',a,\
    location.hostname].join(S)})()
    """

    func script(for transport: Transport) -> String {
        switch transport {
        case .playPause:
            return """
            (function(){\(Self.findElement)if(!b)return '';\
            if(b.paused){b.play()}else{b.pause()}return 'OK'})()
            """

        case .next:
            return """
            (function(){var q=['.ytp-next-button',\
            '[data-testid=control-button-skip-forward]','.skipControl__next',\
            '[aria-label=Next]','[title=Next]'];\
            for(var i=0;i<q.length;i++){var n=document.querySelector(q[i]);\
            if(n&&!n.disabled){n.click();return 'OK'}}return ''})()
            """

        case .previous:
            // Most players restart the track rather than skipping back when the
            // position is past a few seconds; seeking to zero matches that.
            return """
            (function(){var q=['.ytp-prev-button',\
            '[data-testid=control-button-skip-back]','.skipControl__previous',\
            '[aria-label=Previous]','[title=Previous]'];\
            for(var i=0;i<q.length;i++){var n=document.querySelector(q[i]);\
            if(n&&!n.disabled){n.click();return 'OK'}}\
            \(Self.findElement)if(b){b.currentTime=0;return 'OK'}return ''})()
            """
        }
    }
}
