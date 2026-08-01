import Darwin
import Foundation

struct LiveActivity: Codable, Equatable, Identifiable {
    enum State: String, Codable { case active, finished }

    let id: String
    var title: String
    var subtitle: String?
    var progress: Double?
    var startedAt: Date
    var updatedAt: Date
    var state: State
    var completionMessage: String?

    static func isValidID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 48 && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
        }
    }
}

@MainActor
final class LiveActivityService: ObservableObject {
    @Published private(set) var active: [LiveActivity] = []

    nonisolated static var signalDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".bondex-notch/live", isDirectory: true)
    }

    private static let staleAfter: TimeInterval = 24 * 60 * 60
    private let events: EventCenter
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var expiryTimer: Timer?

    init(events: EventCenter) { self.events = events }

    func start() {
        stop()
        try? FileManager.default.createDirectory(
            at: Self.signalDirectory, withIntermediateDirectories: true
        )
        watch()
        refresh()
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
        expiryTimer?.invalidate()
        expiryTimer = nil
        active = []
    }

    func seedForPreview(_ activities: [LiveActivity]) {
        stop()
        active = activities
    }

    private func watch() {
        descriptor = open(Self.signalDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in onMainActor { self?.refresh() } }
        source.setCancelHandler { [descriptor] in if descriptor >= 0 { close(descriptor) } }
        source.resume()
        self.source = source
    }

    private func refresh() {
        let now = Date()
        var fresh: [LiveActivity] = []
        for url in Self.signalURLs() {
            guard let activity = Self.read(url: url) else { continue }
            if activity.state == .finished {
                events.post(NotchEvent(
                    kind: .live,
                    title: "\(activity.title) finished",
                    subtitle: activity.completionMessage ?? activity.subtitle
                ))
                try? FileManager.default.removeItem(at: url)
            } else if now.timeIntervalSince(activity.updatedAt) < Self.staleAfter {
                fresh.append(activity)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        fresh.sort { $0.updatedAt > $1.updatedAt }
        if fresh != active { active = fresh }
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard !active.isEmpty else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            onMainActor { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    nonisolated static func signalURLs(
        directory: URL = signalDirectory,
        fileManager: FileManager = .default
    ) -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { $0.pathExtension == "json" && isValidFilename($0.deletingPathExtension().lastPathComponent) }
    }

    nonisolated static func read(
        id: String,
        directory: URL = signalDirectory
    ) -> LiveActivity? {
        read(url: signalURL(id: id, directory: directory))
    }

    nonisolated private static func read(url: URL) -> LiveActivity? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LiveActivity.self, from: data)
    }

    nonisolated static func startActivity(
        id: String,
        title: String,
        subtitle: String?,
        progress: Double?,
        directory: URL = signalDirectory
    ) throws {
        let now = Date()
        try write(LiveActivity(
            id: id,
            title: title,
            subtitle: subtitle,
            progress: progress,
            startedAt: now,
            updatedAt: now,
            state: .active,
            completionMessage: nil
        ), directory: directory)
    }

    nonisolated static func updateActivity(
        id: String,
        title: String?,
        subtitle: String?,
        progress: Double?,
        directory: URL = signalDirectory
    ) throws {
        guard var activity = read(id: id, directory: directory), activity.state == .active else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "No live activity named \"\(id)\"."
            ])
        }
        if let title { activity.title = title }
        if let subtitle { activity.subtitle = subtitle }
        if let progress { activity.progress = progress }
        activity.updatedAt = Date()
        try write(activity, directory: directory)
    }

    nonisolated static func finishActivity(
        id: String,
        message: String?,
        directory: URL = signalDirectory
    ) throws {
        guard var activity = read(id: id, directory: directory) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "No live activity named \"\(id)\"."
            ])
        }
        activity.state = .finished
        activity.completionMessage = message
        activity.updatedAt = Date()
        try write(activity, directory: directory)
    }

    nonisolated private static func write(_ activity: LiveActivity, directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(activity)
        try data.write(to: signalURL(id: activity.id, directory: directory), options: .atomic)
    }

    nonisolated private static func signalURL(id: String, directory: URL) -> URL {
        directory.appendingPathComponent(id).appendingPathExtension("json")
    }

    nonisolated private static func isValidFilename(_ value: String) -> Bool {
        LiveActivity.isValidID(value)
    }
}
