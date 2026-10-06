import AppKit
import Foundation

struct FileActivity: Identifiable, Equatable {
    let id: String              // Stable across samples: the file path.
    var name: String
    var url: URL
    var byteCount: Int64
    var bytesPerSecond: Double
    var isComplete: Bool
    var startedAt: Date
    var finishedAt: Date?

    /// Browsers write to a sidecar file while downloading; the final name is
    /// the sidecar name minus its suffix.
    static let inProgressExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload"]

    var displayName: String { Self.displayName(for: url) }

    static func displayName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        guard inProgressExtensions.contains(ext) else { return url.lastPathComponent }
        return url.deletingPathExtension().lastPathComponent
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Watches the Downloads folder and reports in-flight and recently finished
/// transfers.
///
/// Uses a directory-level dispatch source rather than polling, then diffs the
/// contents. Growth between diffs gives the transfer rate.
@MainActor
final class FileActivityService: ObservableObject {

    @Published private(set) var activities: [FileActivity] = []
    @Published private(set) var accessDenied = false

    private let events: EventCenter
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pollTimer: Timer?
    private var watchedURL: URL?
    private var previousSizes: [String: (bytes: Int64, at: Date)] = [:]
    /// Files already present when watching began. They are history, not activity.
    private var baseline: Set<String> = []
    /// When each tracked transfer was first seen and, once complete, finished.
    ///
    /// Kept for every new file rather than only the dozen on screen. Deriving it
    /// from the visible list meant a file pushed past the cap came back on the
    /// next scan as if it were new — announced again, banner and all, and
    /// sorted to the top where it pushed the next one out.
    private var records: [String: (startedAt: Date, finishedAt: Date?)] = [:]
    /// Completions already posted. One banner per file, however often the
    /// directory changes afterwards.
    private var announced: Set<String> = []
    /// Finished transfers the user cleared from the list.
    private var dismissed: Set<String> = []

    /// The first read of the folder is in flight.
    private var isStarting = false
    /// Bumped by `stop()`, so a read that answers after it is dropped.
    private var startToken = 0

    /// How many transfers the tab lists.
    static let visibleLimit = 12

    init(events: EventCenter) {
        self.events = events
    }

    /// Idempotent for the folder already being watched. Every preference change
    /// asks for this again, and re-taking the baseline on each one silently
    /// filed everything already reported under "was here before", emptying the
    /// Files tab.
    func start(directory: URL? = nil) {
        let target = directory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let target else { return }
        if watchedURL == target, source != nil || isStarting { return }

        stop()
        watchedURL = target
        isStarting = true
        let token = startToken

        // The first read of Downloads is what raises the Files and Folders
        // prompt, and it blocks its thread until someone answers. It used to
        // run on the main thread during launch — before the panel's first frame
        // was committed — so on a first launch, or after any rebuild with a new
        // ad-hoc signature, the notch and the menu-bar item simply did not
        // appear until the dialog was found and dismissed.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let existing = Self.contents(of: target)
            onMainActor { self?.finishStart(target: target, existing: existing, token: token) }
        }
    }

    private func finishStart(target: URL, existing: [URL]?, token: Int) {
        // A stop, or a start for another folder, arrived while reading.
        guard token == startToken, watchedURL == target else { return }
        isStarting = false

        guard let existing else {
            accessDenied = true
            return
        }
        accessDenied = false
        baseline = Set(existing.map(\.path))
        records.removeAll()
        announced.removeAll()
        dismissed.removeAll()
        activities = []

        descriptor = open(target.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.files.error("Could not open \(target.path, privacy: .public) for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            onMainActor { self?.scan() }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source

        // The dispatch source fires on directory mutations, but a file growing
        // in place does not always mutate the directory, so also poll while
        // something is in flight.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            onMainActor {
                guard let self, self.activities.contains(where: { !$0.isComplete }) else { return }
                self.scan()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        scan()
    }

    func stop() {
        startToken &+= 1
        isStarting = false
        source?.cancel()
        source = nil
        descriptor = -1
        pollTimer?.invalidate()
        pollTimer = nil
        previousSizes.removeAll()
    }

    func reveal(_ activity: FileActivity) {
        NSWorkspace.shared.activateFileViewerSelecting([activity.url])
    }

    /// Clears finished transfers for good: they stay out of the list on later
    /// scans instead of reappearing — and re-announcing themselves — the next
    /// time anything in the folder changes.
    func clearFinished() {
        let finished = activities.filter(\.isComplete).map(\.id)
        dismissed.formUnion(finished)
        finished.forEach { records.removeValue(forKey: $0) }
        activities.removeAll(where: \.isComplete)
    }

    var hasFinished: Bool { activities.contains(where: \.isComplete) }

    // MARK: Scanning

    nonisolated private static func contents(of directory: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
    }

    private func scan() {
        guard let watchedURL, let urls = Self.contents(of: watchedURL) else { return }

        let now = Date()
        var next: [FileActivity] = []
        var seen: Set<String> = []

        for url in urls {
            let path = url.path
            seen.insert(path)

            // Pre-existing files are not activity — unless a partial download
            // for them is what we saw first.
            if baseline.contains(path) || dismissed.contains(path) { continue }

            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            let isPartial = FileActivity.inProgressExtensions
                .contains(url.pathExtension.lowercased())

            let bytes: Int64
            if values?.isDirectory == true {
                // Safari downloads into a `.download` *package* — a folder
                // holding the partial file — so skipping directories outright
                // hid every Safari transfer until it had already finished.
                guard isPartial else { continue }
                bytes = Self.packageSize(url)
            } else {
                bytes = Int64(values?.fileSize ?? 0)
            }

            var rate: Double = 0
            if let previous = previousSizes[path] {
                let elapsed = now.timeIntervalSince(previous.at)
                if elapsed > 0.2, bytes > previous.bytes {
                    rate = Double(bytes - previous.bytes) / elapsed
                }
            }
            previousSizes[path] = (bytes, now)

            var record = records[path] ?? (startedAt: now, finishedAt: nil)
            let isComplete = !isPartial

            // A file that appeared complete on its first sighting is a finished
            // transfer we never saw start; still worth reporting once.
            if isComplete, record.finishedAt == nil { record.finishedAt = now }
            if isComplete, announced.insert(path).inserted {
                events.post(NotchEvent(
                    kind: .download,
                    title: FileActivity.displayName(for: url),
                    subtitle: "Download complete · \(bytes.formattedBytes)"
                ))
            }
            records[path] = record

            next.append(FileActivity(
                id: path,
                name: url.lastPathComponent,
                url: url,
                byteCount: bytes,
                bytesPerSecond: rate,
                isComplete: isComplete,
                startedAt: record.startedAt,
                finishedAt: record.finishedAt
            ))
        }

        // Forget files that are gone, so a later download reusing the name is
        // reported afresh.
        previousSizes = previousSizes.filter { seen.contains($0.key) }
        records = records.filter { seen.contains($0.key) }
        announced.formIntersection(seen)
        dismissed.formIntersection(seen)

        // A partial file disappearing usually means it was renamed to its final
        // name, which the loop above will already have picked up.
        activities = next
            .sorted { lhs, rhs in
                if lhs.isComplete != rhs.isComplete { return !lhs.isComplete }
                return (lhs.finishedAt ?? lhs.startedAt) > (rhs.finishedAt ?? rhs.startedAt)
            }
            .prefix(Self.visibleLimit)
            .map { $0 }
    }

    /// Bytes received so far by a download package: the sum of what it holds.
    private static func packageSize(_ url: URL) -> Int64 {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return children.reduce(Int64(0)) { total, child in
            let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { return total }
            return total + Int64(values?.fileSize ?? 0)
        }
    }
}
