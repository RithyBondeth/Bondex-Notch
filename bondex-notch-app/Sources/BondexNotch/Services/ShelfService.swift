import AppKit
import Foundation
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    let addedAt: Date
    /// Finds the file again after it moves or is renamed, and across launches.
    var bookmark: Data?

    var name: String { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    var byteCount: Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    var existsOnDisk: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

/// A tray that outlasts a restart. Drag files onto the notch to park them,
/// drag them out wherever they need to go.
///
/// Finder files stay where they are and are remembered by bookmark, so one
/// that moves or is renamed is found again. Image-only drops are copied into
/// Application Support and deleted when their shelf item is removed.
@MainActor
final class ShelfService: ObservableObject {

    @Published private(set) var items: [ShelfItem] = []

    /// Finder files arrive as file URLs. The floating thumbnail shown after a
    /// macOS screenshot is different: it advertises only image data, so both
    /// representations have to be accepted at the drop boundary.
    static let acceptedDropTypes: [UTType] = [.fileURL, .image]

    private let events: EventCenter
    private let maxItems = 20
    /// Where the shelf is kept between launches; nil keeps it in memory only.
    private let defaults: UserDefaults?
    private static let defaultsKey = "com.bondex.notch.shelf"

    /// Copies the shelf made of dropped image data — a screenshot thumbnail,
    /// an image dragged out of a browser — which have no file of their own.
    ///
    /// Application Support rather than the temporary folder: the shelf
    /// survives a restart, and macOS empties the temporary folder on its own
    /// schedule, which would leave restored tiles pointing at nothing.
    private static var copiesDirectory: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.bondex.notch", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
    }

    private struct StoredItem: Codable {
        var bookmark: Data
        var addedAt: Date
    }

    init(events: EventCenter, defaults: UserDefaults? = nil) {
        self.events = events
        self.defaults = defaults
        restore()
    }

    var isEmpty: Bool { items.isEmpty }

    @discardableResult
    func add(urls: [URL]) -> Int {
        let existing = Set(items.map(\.url.standardizedFileURL))
        let fresh = urls
            .map(\.standardizedFileURL)
            .filter { !existing.contains($0) && FileManager.default.fileExists(atPath: $0.path) }

        guard !fresh.isEmpty else { return 0 }

        let now = Date()
        items.insert(contentsOf: fresh.map {
            ShelfItem(url: $0, addedAt: now, bookmark: Self.bookmark(for: $0))
        }, at: 0)
        if items.count > maxItems {
            let overflow = items.suffix(from: maxItems)
            overflow.forEach { removeShelfCopy(at: $0.url) }
            items.removeLast(items.count - maxItems)
        }
        persist()

        events.post(NotchEvent(
            kind: .shelf,
            title: fresh.count == 1
                ? fresh[0].lastPathComponent
                : "\(fresh.count) items added",
            subtitle: "On the shelf"
        ))
        return fresh.count
    }

    var hasMissingItems: Bool {
        items.contains { !$0.existsOnDisk }
    }

    func pruneMissingItems() {
        refreshLocations()
        let missing = items.filter { !$0.existsOnDisk }
        missing.forEach { removeShelfCopy(at: $0.url) }
        items.removeAll { !$0.existsOnDisk }
        persist()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        removeShelfCopy(at: item.url)
        persist()
    }

    func clear() {
        items.forEach { removeShelfCopy(at: $0.url) }
        items.removeAll()
        persist()
    }

    /// Follows files that moved or were renamed since they were shelved.
    ///
    /// A tile used to keep the path it was dropped with, so moving the file
    /// left it marked missing for good. The bookmark finds it at its new path.
    func refreshLocations() {
        var changed = false
        for index in items.indices where !items[index].existsOnDisk {
            guard let bookmark = items[index].bookmark,
                  let (url, fresh) = Self.resolve(bookmark) else { continue }
            items[index].url = url
            items[index].bookmark = fresh
            changed = true
        }
        if changed { persist() }
    }

    // MARK: Persistence

    private func restore() {
        guard let data = defaults?.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode([StoredItem].self, from: data) else { return }
        // A file that can no longer be found at all is dropped quietly; one
        // that merely moved comes back at its new path.
        items = stored.compactMap { entry in
            guard let (url, bookmark) = Self.resolve(entry.bookmark),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ShelfItem(url: url, addedAt: entry.addedAt, bookmark: bookmark)
        }
        if items.count != stored.count { persist() }
    }

    private func persist() {
        guard let defaults else { return }
        let stored = items.compactMap { item -> StoredItem? in
            guard let bookmark = item.bookmark ?? Self.bookmark(for: item.url) else { return nil }
            return StoredItem(bookmark: bookmark, addedAt: item.addedAt)
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// The bookmark's file, and the bookmark to keep — a fresh one if the old
    /// had gone stale.
    private static func resolve(_ bookmark: Data) -> (URL, Data)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isInTrash(url) else { return nil }
        return (url, isStale ? (Self.bookmark(for: url) ?? bookmark) : bookmark)
    }

    /// A bookmark follows a file into the Trash too. Deleting it in Finder is
    /// a move there, and should take the tile with it.
    static func isInTrash(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Resolves the file URLs out of a drop. Returns on the main actor once
    /// every provider has reported.
    func resolve(providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                group.addTask {
                    if let url = await Self.loadFileURL(from: provider) { return url }
                    return await Self.materializeImage(from: provider)
                }
            }
            var urls: [URL] = []
            for await url in group {
                if let url { urls.append(url) }
            }
            return urls
        }
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return nil
        }

        if let url = await withCheckedContinuation({ continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }) {
            return url
        }

        // Some Finder extensions vend the file-url representation as encoded
        // data or NSURL instead of a Swift URL object.
        return await withCheckedContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                let url: URL?
                switch item {
                case let value as URL:
                    url = value
                case let value as NSURL:
                    url = value as URL
                case let data as Data:
                    url = Self.decodeURL(data)
                case let string as String:
                    url = URL(string: string) ?? URL(fileURLWithPath: string)
                default:
                    url = nil
                }
                continuation.resume(returning: url)
            }
        }
    }

    nonisolated private static func decodeURL(_ data: Data) -> URL? {
        guard let string = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return nil }
        return URL(string: string) ?? URL(fileURLWithPath: string)
    }

    /// Turns an image-only drag (notably the floating macOS screenshot
    /// thumbnail) into a file of the shelf's own so the rest of it can keep its
    /// URL-based model and drag the item back out normally.
    private static func materializeImage(from provider: NSItemProvider) async -> URL? {
        guard let identifier = preferredImageIdentifier(from: provider) else { return nil }
        guard let data = await withCheckedContinuation({ continuation in
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }), !data.isEmpty else { return nil }

        let type = UTType(identifier)
        let fileExtension = type?.preferredFilenameExtension ?? "png"
        let directory = copiesDirectory
        let filename = "Screenshot-\(UUID().uuidString.prefix(8)).\(fileExtension)"
        let url = directory.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.shelf.error("Could not materialize dropped image: \(error.localizedDescription)")
            return nil
        }
    }

    private static func preferredImageIdentifier(from provider: NSItemProvider) -> String? {
        let identifiers = provider.registeredTypeIdentifiers.filter {
            UTType($0)?.conforms(to: .image) == true
        }
        return identifiers.first(where: { $0 == UTType.png.identifier })
            ?? identifiers.first(where: { $0 == UTType.jpeg.identifier })
            ?? identifiers.first
    }

    private func removeShelfCopy(at url: URL) {
        guard Self.isShelfCopy(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Whether the file is one the shelf made itself, and so is the shelf's
    /// to delete when its tile goes.
    static func isShelfCopy(_ url: URL) -> Bool {
        let directory = copiesDirectory.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate.hasPrefix(directory + "/")
    }
}
