import AppKit
import Foundation

struct NowPlaying: Equatable {

    var source: MediaApp
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: TimeInterval
    var position: TimeInterval
    var artwork: NSImage?
    /// Set instead of `artwork` when the art has to be fetched over the network
    /// (Spotify and every browser report a URL, not bytes).
    var artworkURL: URL?
    /// When `position` was measured, so the UI can advance it between polls
    /// instead of stepping once a second.
    var sampledAt = Date()
    /// False when playback can be seen but not driven — a browser read from its
    /// window title has no handle on the media element to play or pause. The UI
    /// hides the transport rather than offering buttons that do nothing.
    var supportsTransport = true

    /// True for a live stream, which reports no meaningful duration.
    var isLive: Bool { duration <= 0 }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// `position` carried forward by wall-clock time. Polling is once a second;
    /// this is what keeps the progress bar and elapsed clock moving smoothly in
    /// between.
    func position(at date: Date) -> TimeInterval {
        guard isPlaying else { return position }
        let elapsed = max(date.timeIntervalSince(sampledAt), 0)
        guard duration > 0 else { return position + elapsed }
        return min(position + elapsed, duration)
    }

    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(position(at: date) / duration, 0), 1)
    }

    static func == (lhs: NowPlaying, rhs: NowPlaying) -> Bool {
        lhs.source == rhs.source
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.isPlaying == rhs.isPlaying
            && abs(lhs.duration - rhs.duration) < 0.5
            && abs(lhs.position - rhs.position) < 0.9
            && lhs.artwork === rhs.artwork
            && lhs.artworkURL == rhs.artworkURL
    }

    /// Identity of the *track*, ignoring transport position. Used to decide when
    /// to refetch artwork and when to announce a change.
    var trackKey: String {
        "\(source.bundleIdentifier)|\(title)|\(artist)|\(album)"
    }
}

/// Reports what the Mac is playing, wherever it is playing from.
///
/// macOS has no public system-wide Now Playing API: `MPNowPlayingInfoCenter`
/// only describes the *current process*, and the private MediaRemote framework
/// has been entitlement-gated since macOS 15.4. So playback is read from the
/// apps themselves — Music and Spotify over their scripting dictionaries, and
/// browsers by evaluating a small script in the tab that owns the media, which
/// is what makes YouTube and other web players visible.
@MainActor
final class NowPlayingService: ObservableObject {

    @Published private(set) var nowPlaying: NowPlaying? {
        didSet { refreshPalette() }
    }
    /// Colours pulled out of the current artwork, for the panel to light itself
    /// from. Nil whenever there is no artwork to read — which is often, so every
    /// consumer has to have an answer for that rather than treating it as an
    /// error case.
    @Published private(set) var palette: ArtworkPalette?
    /// True when Automation access was denied for an app we tried to read.
    @Published private(set) var automationDenied = false
    /// Set when a running browser still has "Allow JavaScript from Apple Events"
    /// turned off, which is the one thing the user has to do by hand for web
    /// media to appear.
    @Published private(set) var blockedBrowser: MediaApp?

    /// Whether browser tabs are scanned at all. Owned by settings.
    var includeBrowsers = true {
        didSet {
            guard includeBrowsers != oldValue else { return }
            if !includeBrowsers { blockedBrowser = nil }
            reader.resetBrowserState()
        }
    }

    private var timer: Timer?
    private let reader = MediaReader()
    private let events: EventCenter
    private var lastAnnouncedTrackKey: String?
    private var artworkKey: String?
    private var isSampling = false
    private var artworkTask: Task<Void, Never>?
    private let paletteCache = ArtworkPaletteCache()
    /// See `seedForPreview`. Always false in the running app.
    private var isPreviewSeeded = false

    init(events: EventCenter) {
        self.events = events
    }

    func start(interval: TimeInterval = 1.0) {
        guard !isPreviewSeeded else { return }
        stop()
        refresh()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            onMainActor { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        artworkTask?.cancel()
        artworkTask = nil
    }

    /// Publishes a track without polling for it, so the offscreen preview tool can
    /// render the playback states on a machine where nothing happens to be
    /// playing. Nothing in the running app calls this.
    ///
    /// Latches polling off for good: a read already in flight would otherwise land
    /// afterwards and clear the seeded track back to "nothing playing".
    func seedForPreview(_ track: NowPlaying?) {
        stop()
        isPreviewSeeded = true
        nowPlaying = track
    }

    // MARK: Transport

    func playPause() { perform(.playPause) }
    func next() { perform(.next) }
    func previous() { perform(.previous) }

    private func perform(_ command: MediaReader.Transport) {
        guard let track = nowPlaying, track.supportsTransport else { return }
        let source = track.source
        let reader = self.reader
        Task.detached(priority: .userInitiated) {
            reader.perform(command, on: source)
            // Reflect the new transport state without waiting for the next tick.
            try? await Task.sleep(nanoseconds: 180_000_000)
            await MainActor.run { self.refresh() }
        }
    }

    // MARK: Polling

    private func refresh() {
        // A blocked Apple Event can take seconds; never stack requests.
        guard !isSampling else { return }
        isSampling = true

        // Which apps are running is an AppKit question, and `NSWorkspace` traps if
        // it is asked off the main thread — so the target list is resolved here and
        // handed to the reader, which then only talks to Apple Events.
        let reader = self.reader
        let players = MediaApp.runningPlayers()
        let browsers = includeBrowsers ? MediaApp.runningBrowsers() : []

        Task.detached(priority: .utility) {
            let result = reader.read(players: players, browsers: browsers)
            await MainActor.run { self.apply(result) }
        }
    }

    private func apply(_ result: MediaReader.Result) {
        isSampling = false
        guard !isPreviewSeeded else { return }
        automationDenied = result.automationDenied
        blockedBrowser = includeBrowsers ? result.blockedBrowser : nil

        guard var track = result.track else {
            nowPlaying = nil
            lastAnnouncedTrackKey = nil
            artworkKey = nil
            artworkTask?.cancel()
            artworkTask = nil
            return
        }

        // Artwork is fetched once per track, so carry the current image across
        // the position-only updates in between.
        if track.artwork == nil, track.trackKey == artworkKey {
            track.artwork = nowPlaying?.artwork
        } else if track.artwork != nil {
            artworkKey = track.trackKey
        }

        if track.trackKey != lastAnnouncedTrackKey, track.isPlaying, !track.title.isEmpty {
            lastAnnouncedTrackKey = track.trackKey
            events.post(NotchEvent(
                kind: .music,
                title: track.title,
                subtitle: track.artist.isEmpty ? track.source.displayName : track.artist
            ))
        }

        nowPlaying = track
        fetchArtworkIfNeeded(for: track)
    }

    /// Keeps `palette` in step with the artwork on `nowPlaying`.
    ///
    /// `nowPlaying` is republished once a second whether or not anything about
    /// the track changed, so both the extraction *and* the publish have to be
    /// suppressed when nothing moved: the cache handles the first, and comparing
    /// the result handles the second. Without the comparison every consumer of
    /// the palette would re-render every second for no reason.
    private func refreshPalette() {
        let extracted = paletteCache.palette(
            for: nowPlaying?.artwork,
            key: nowPlaying?.trackKey
        )
        guard extracted != palette else { return }
        palette = extracted
    }

    /// Remote artwork is fetched off the Apple Event lock, so a slow CDN can
    /// never wedge the transport controls.
    private func fetchArtworkIfNeeded(for track: NowPlaying) {
        guard track.artwork == nil,
              let url = track.artworkURL,
              track.trackKey != artworkKey else { return }

        artworkKey = track.trackKey
        artworkTask?.cancel()
        let key = track.trackKey

        artworkTask = Task { [weak self] in
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let image = NSImage(data: data) else { return }

            guard let self, !Task.isCancelled else { return }
            // The track may have moved on while the image was in flight.
            guard self.nowPlaying?.trackKey == key else { return }
            self.nowPlaying?.artwork = image
        }
    }
}

// MARK: - Reading

/// Aggregates every place playback can be read from, in priority order.
///
/// Not `@MainActor`: it runs on a background queue behind a shared Apple Event
/// lock, because a single blocked event can stall for seconds.
private final class MediaReader: @unchecked Sendable {

    typealias Transport = BrowserMediaReader.Transport

    struct Result {
        var track: NowPlaying?
        var automationDenied = false
        var blockedBrowser: MediaApp?
    }

    private let engine = AppleScriptEngine()
    private let browsers: BrowserMediaReader

    init() {
        browsers = BrowserMediaReader(engine: engine)
    }

    func resetBrowserState() {
        engine.withLock { browsers.reset() }
    }

    // MARK: Reading

    /// Music and Spotify win over a browser tab, and a playing source wins over a
    /// paused one — so a paused YouTube tab never hides the album that is actually
    /// playing.
    ///
    /// Both lists are resolved by the caller on the main actor; an empty
    /// `browsers` means web media is switched off or no browser is open.
    func read(players: [MediaApp], browsers browserApps: [MediaApp]) -> Result {
        engine.withLock {
            var result = Result()
            var paused: NowPlaying?

            for app in players {
                let outcome = readPlayer(app)
                if outcome.failure == .automationDenied { result.automationDenied = true }
                guard let track = outcome.track else { continue }
                if track.isPlaying {
                    result.track = track
                    return result
                }
                if paused == nil { paused = track }
            }

            if !browserApps.isEmpty {
                let reading = browsers.read(in: browserApps)
                switch reading.failure {
                case .automationDenied: result.automationDenied = true
                case .javaScriptDisabled: result.blockedBrowser = reading.failedApp
                default: break
                }
                if let track = reading.track {
                    if track.isPlaying {
                        result.track = track
                        return result
                    }
                    if paused == nil { paused = track }
                }
            }

            result.track = paused
            return result
        }
    }

    // MARK: Native players

    private func readPlayer(_ app: MediaApp) -> BrowserMediaReader.Reading {
        // Spotify reports duration in milliseconds, Music in seconds.
        let durationExpression = app.engine == .spotify
            ? "((duration of current track) / 1000)"
            : "(duration of current track)"

        let script = """
        tell application "\(app.scriptName)"
            if player state is stopped then return "STOPPED"
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set trackDuration to \(durationExpression)
            set trackPosition to player position
            set playState to (player state as text)
            return trackName & "\\n" & trackArtist & "\\n" & trackAlbum & "\\n" ¬
                & trackDuration & "\\n" & trackPosition & "\\n" & playState
        end tell
        """

        let outcome = engine.run(script)
        if let failure = outcome.failure {
            return BrowserMediaReader.Reading(track: nil, failure: failure)
        }
        guard let raw = outcome.value, raw != "STOPPED" else {
            return BrowserMediaReader.Reading(track: nil, failure: nil)
        }

        let fields = raw.components(separatedBy: "\n")
        guard fields.count >= 6 else {
            return BrowserMediaReader.Reading(track: nil, failure: nil)
        }

        var track = NowPlaying(
            source: app,
            title: fields[0],
            artist: fields[1],
            album: fields[2],
            isPlaying: fields[5].lowercased().contains("playing"),
            duration: Double(fields[3]) ?? 0,
            position: Double(fields[4]) ?? 0,
            artwork: nil
        )

        switch app.engine {
        case .music:
            // Only Music.app hands over raw artwork bytes, and it is cheap
            // enough to read inline.
            track.artwork = readMusicArtwork()
        case .spotify:
            track.artworkURL = engine
                .run("tell application \"Spotify\" to return artwork url of current track")
                .value
                .flatMap(URL.init(string:))
        case .webkit, .chromium:
            break
        }

        return BrowserMediaReader.Reading(track: track, failure: nil)
    }

    private func readMusicArtwork() -> NSImage? {
        let script = """
        tell application "Music"
            if (count of artworks of current track) is 0 then return missing value
            return data of artwork 1 of current track
        end tell
        """
        guard let data = engine.runForData(script) else { return nil }
        return NSImage(data: data)
    }

    // MARK: Transport

    func perform(_ transport: Transport, on app: MediaApp) {
        engine.withLock {
            if app.isBrowser {
                _ = browsers.perform(transport, on: app)
                return
            }

            let verb: String
            switch transport {
            case .playPause: verb = "playpause"
            case .next: verb = "next track"
            // A single `previous track` already restarts the track when the
            // position is past ~2s, which is what users expect from one tap.
            case .previous: verb = "previous track"
            }
            _ = engine.run("tell application \"\(app.scriptName)\" to \(verb)")
        }
    }
}
