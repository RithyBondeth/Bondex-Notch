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

    var displayName: String {
        let ext = url.pathExtension.lowercased()
        guard Self.inProgressExtensions.contains(ext) else { return name }
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

    init(events: EventCenter) {
        self.events = events
    }

    func start(directory: URL? = nil) {
        stop()

        let target = directory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let target else { return }
        watchedURL = target

        // Reading Downloads triggers the TCC prompt on first access.
        guard let existing = contents(of: target) else {
            accessDenied = true
            return
        }
        accessDenied = false
        baseline = Set(existing.map(\.path))

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
            MainActor.assumeIsolated { self?.scan() }
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
            MainActor.assumeIsolated {
                guard let self, self.activities.contains(where: { !$0.isComplete }) else { return }
                self.scan()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        scan()
    }

    func stop() {
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

    func clearFinished() {
        activities.removeAll(where: \.isComplete)
    }

    // MARK: Scanning

    private func contents(of directory: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
    }

    private func scan() {
        guard let watchedURL, let urls = contents(of: watchedURL) else { return }

        let now = Date()
        var next: [FileActivity] = []
        var seen: Set<String> = []

        for url in urls {
            let path = url.path
            seen.insert(path)

            // Pre-existing files are not activity — unless a partial download
            // for them is what we saw first.
            if baseline.contains(path) { continue }

            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true { continue }
            let bytes = Int64(values?.fileSize ?? 0)

            let isPartial = FileActivity.inProgressExtensions
                .contains(url.pathExtension.lowercased())

            var rate: Double = 0
            if let previous = previousSizes[path] {
                let elapsed = now.timeIntervalSince(previous.at)
                if elapsed > 0.2, bytes > previous.bytes {
                    rate = Double(bytes - previous.bytes) / elapsed
                }
            }
            previousSizes[path] = (bytes, now)

            let existing = activities.first { $0.id == path }
            var activity = FileActivity(
                id: path,
                name: url.lastPathComponent,
                url: url,
                byteCount: bytes,
                bytesPerSecond: rate,
                isComplete: !isPartial,
                startedAt: existing?.startedAt ?? now,
                finishedAt: existing?.finishedAt
            )

            // A file that appeared complete on its first sighting is a finished
            // transfer we never saw start; still worth reporting once.
            if activity.isComplete, existing?.isComplete != true {
                activity.finishedAt = now
                events.post(NotchEvent(
                    kind: .download,
                    title: activity.displayName,
                    subtitle: "Download complete · \(bytes.formattedBytes)"
                ))
            }

            next.append(activity)
        }

        // Drop entries whose file is gone, and forget stale rate samples.
        previousSizes = previousSizes.filter { seen.contains($0.key) }

        // A partial file disappearing usually means it was renamed to its final
        // name, which the loop above will already have picked up.
        activities = next
            .sorted { lhs, rhs in
                if lhs.isComplete != rhs.isComplete { return !lhs.isComplete }
                return (lhs.finishedAt ?? lhs.startedAt) > (rhs.finishedAt ?? rhs.startedAt)
            }
            .prefix(12)
            .map { $0 }
    }
}
