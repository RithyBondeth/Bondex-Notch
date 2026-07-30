import AppKit
import Foundation

struct NowPlaying: Equatable {
    enum Source: String {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var displayName: String {
            switch self {
            case .music: return "Music"
            case .spotify: return "Spotify"
            }
        }

        /// AppleScript application name.
        var scriptName: String {
            switch self {
            case .music: return "Music"
            case .spotify: return "Spotify"
            }
        }
    }

    var source: Source
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: TimeInterval
    var position: TimeInterval
    var artwork: NSImage?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
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
    }

    /// Identity of the *track*, ignoring transport position. Used to decide
    /// when to refetch artwork and when to announce a change.
    var trackKey: String { "\(source.rawValue)|\(title)|\(artist)|\(album)" }
}

/// Reads and controls playback in Music.app and Spotify.
///
/// macOS has no public system-wide Now Playing API. `MPNowPlayingInfoCenter`
/// only reports the *current process*, and the private MediaRemote framework
/// was gated in macOS 15.4. Scripting the two players that expose an AppleScript
/// dictionary is the supported path; it costs an Automation consent prompt the
/// first time (see `NSAppleEventsUsageDescription` in Info.plist) and covers
/// the large majority of desktop listening.
@MainActor
final class NowPlayingService: ObservableObject {

    @Published private(set) var nowPlaying: NowPlaying?
    /// True when the user denied (or has not yet granted) Automation access.
    @Published private(set) var automationDenied = false

    private var timer: Timer?
    private let runner = AppleScriptRunner()
    private let events: EventCenter
    private var lastAnnouncedTrackKey: String?
    private var cachedArtworkKey: String?
    private var isSampling = false

    init(events: EventCenter) {
        self.events = events
    }

    func start(interval: TimeInterval = 1.0) {
        stop()
        refresh()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Transport

    func playPause() { perform(.playPause) }
    func next() { perform(.next) }
    func previous() { perform(.previous) }

    private func perform(_ command: AppleScriptRunner.Command) {
        guard let source = nowPlaying?.source else { return }
        let runner = self.runner
        Task.detached(priority: .userInitiated) {
            runner.perform(command, on: source)
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

        let runner = self.runner
        let wantsArtworkFor = cachedArtworkKey
        Task.detached(priority: .utility) {
            let result = runner.readNowPlaying(currentArtworkKey: wantsArtworkFor)
            await MainActor.run { self.apply(result) }
        }
    }

    private func apply(_ result: AppleScriptRunner.ReadResult) {
        isSampling = false
        automationDenied = result.permissionDenied

        guard var track = result.nowPlaying else {
            nowPlaying = nil
            lastAnnouncedTrackKey = nil
            cachedArtworkKey = nil
            return
        }

        // Artwork is only refetched on track change, so carry the current one
        // across position-only updates.
        if track.artwork == nil, track.trackKey == cachedArtworkKey {
            track.artwork = nowPlaying?.artwork
        } else if track.artwork != nil {
            cachedArtworkKey = track.trackKey
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
    }
}

// MARK: - AppleScript

/// Serialises every Apple Event onto one queue. `NSAppleScript` is not safe to
/// use from multiple threads concurrently.
private final class AppleScriptRunner: @unchecked Sendable {

    enum Command {
        case playPause, next, previous

        func script(for source: NowPlaying.Source) -> String {
            let app = source.scriptName
            switch self {
            case .playPause: return "tell application \"\(app)\" to playpause"
            case .next: return "tell application \"\(app)\" to next track"
            case .previous:
                // Two `previous track` calls would skip back twice in Music; the
                // single call already restarts the track when past ~2s.
                return "tell application \"\(app)\" to previous track"
            }
        }
    }

    struct ReadResult {
        var nowPlaying: NowPlaying?
        var permissionDenied = false
    }

    private let queue = DispatchQueue(label: "com.bondex.notch.applescript")
    private let lock = NSLock()

    // MARK: Reading

    func readNowPlaying(currentArtworkKey: String?) -> ReadResult {
        lock.lock()
        defer { lock.unlock() }

        var denied = false

        // Music first: if both are running, Music wins unless it is stopped.
        for source in [NowPlaying.Source.music, .spotify] {
            guard isRunning(source) else { continue }
            let outcome = read(source)
            if outcome.denied { denied = true }
            guard var track = outcome.track else { continue }

            if track.trackKey != currentArtworkKey {
                track.artwork = readArtwork(source)
            }
            return ReadResult(nowPlaying: track, permissionDenied: denied)
        }

        return ReadResult(nowPlaying: nil, permissionDenied: denied)
    }

    private func isRunning(_ source: NowPlaying.Source) -> Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: source.rawValue)
            .isEmpty
    }

    private func read(_ source: NowPlaying.Source) -> (track: NowPlaying?, denied: Bool) {
        let app = source.scriptName
        // Spotify reports duration in milliseconds, Music in seconds.
        let durationExpression = source == .spotify
            ? "((duration of current track) / 1000)"
            : "(duration of current track)"

        let script = """
        tell application "\(app)"
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

        let outcome = execute(script)
        if outcome.denied { return (nil, true) }
        guard let raw = outcome.value, raw != "STOPPED" else { return (nil, false) }

        let fields = raw.components(separatedBy: "\n")
        guard fields.count >= 6 else { return (nil, false) }

        return (NowPlaying(
            source: source,
            title: fields[0],
            artist: fields[1],
            album: fields[2],
            isPlaying: fields[5].lowercased().contains("playing"),
            duration: Double(fields[3]) ?? 0,
            position: Double(fields[4]) ?? 0,
            artwork: nil
        ), false)
    }

    /// Only Music.app exposes raw artwork bytes over AppleScript. Spotify
    /// exposes an artwork *URL*, which is fetched over the network instead.
    private func readArtwork(_ source: NowPlaying.Source) -> NSImage? {
        switch source {
        case .music:
            let script = """
            tell application "Music"
                if (count of artworks of current track) is 0 then return missing value
                return data of artwork 1 of current track
            end tell
            """
            var error: NSDictionary?
            guard let apple = NSAppleScript(source: script) else { return nil }
            let descriptor = apple.executeAndReturnError(&error)
            guard error == nil else { return nil }
            let data = descriptor.data
            guard !data.isEmpty else { return nil }
            return NSImage(data: data)

        case .spotify:
            let outcome = execute(
                "tell application \"Spotify\" to return artwork url of current track"
            )
            guard let urlString = outcome.value,
                  let url = URL(string: urlString),
                  let data = fetch(url) else { return nil }
            return NSImage(data: data)
        }
    }

    /// Bounded artwork fetch. This runs while the script lock is held, so an
    /// unresponsive CDN must not be able to wedge the transport controls.
    private func fetch(_ url: URL) -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let semaphore = DispatchSemaphore(value: 0)
        let box = DataBox()
        URLSession.shared.dataTask(with: request) { data, _, _ in
            box.value = data
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + 3.5) == .success else { return nil }
        return box.value
    }

    private final class DataBox: @unchecked Sendable {
        var value: Data?
    }

    // MARK: Writing

    func perform(_ command: Command, on source: NowPlaying.Source) {
        lock.lock()
        defer { lock.unlock() }
        _ = execute(command.script(for: source))
    }

    // MARK: Execution

    private func execute(_ source: String) -> (value: String?, denied: Bool) {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return (nil, false) }
        let descriptor = script.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743: user denied Automation. -600/-609: app quit mid-script.
            let denied = (code == -1743)
            if !denied, code != -600, code != -609, code != 0 {
                Log.music.debug("AppleScript error \(code): \(String(describing: error))")
            }
            return (nil, denied)
        }
        return (descriptor.stringValue, false)
    }
}
