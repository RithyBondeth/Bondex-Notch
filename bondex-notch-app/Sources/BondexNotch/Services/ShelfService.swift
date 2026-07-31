import AppKit
import Foundation
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let addedAt: Date

    var name: String { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    var byteCount: Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}

/// A temporary tray. Drag files onto the notch to park them, drag them out
/// wherever they need to go.
///
/// Only URLs are held — nothing is copied, so removing a shelf item never
/// touches the user's file.
@MainActor
final class ShelfService: ObservableObject {

    @Published private(set) var items: [ShelfItem] = []

    private let events: EventCenter
    private let maxItems = 20

    init(events: EventCenter) {
        self.events = events
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
        items.insert(contentsOf: fresh.map { ShelfItem(url: $0, addedAt: now) }, at: 0)
        if items.count > maxItems { items.removeLast(items.count - maxItems) }

        events.post(NotchEvent(
            kind: .shelf,
            title: fresh.count == 1
                ? fresh[0].lastPathComponent
                : "\(fresh.count) items added",
            subtitle: "On the shelf"
        ))
        return fresh.count
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Resolves a drop into file URLs. Returns on the main actor once every
    /// provider has reported.
    func resolve(providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                group.addTask { await Self.fileURL(from: provider) }
            }
            var urls: [URL] = []
            for await url in group {
                if let url { urls.append(url) }
            }
            return urls
        }
    }

    /// A file on disk for whatever was dropped.
    ///
    /// Most drops are a file URL and are only referenced, never copied. Some have
    /// no file behind them at all: a screenshot dragged straight off its thumbnail
    /// has not been written to disk yet, and an image dragged out of a browser
    /// never will be. Those arrive as raw data, so there is nothing to point at
    /// until it is written somewhere — which is what `stage` does.
    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        if provider.canLoadObject(ofClass: URL.self) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
            // A promised file reports a URL before anything exists at it, and a
            // browser drag reports an https one. Either way, fall through.
            if let url, url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return await stageImage(from: provider)
    }

    /// Writes dropped image data out and returns where it landed.
    private static func stageImage(from provider: NSItemProvider) async -> URL? {
        let candidates: [UTType] = [.png, .jpeg, .heic, .tiff, .gif, .pdf, .image]

        for type in candidates
        where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            let data: Data? = await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(
                    forTypeIdentifier: type.identifier
                ) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            guard let data, !data.isEmpty else { continue }
            if let url = write(data, as: type) { return url }
        }
        return nil
    }

    private static func write(_ data: Data, as type: UTType) -> URL? {
        let directory = stagingDirectory
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
        } catch {
            Log.shelf.error("Could not create the shelf staging folder: \(error.localizedDescription)")
            return nil
        }

        let stamp = Self.stampFormatter.string(from: Date())
        let ext = type.preferredFilenameExtension ?? "png"
        var url = directory.appendingPathComponent("Dropped \(stamp).\(ext)")

        // Two drops in the same second must not overwrite one another.
        var attempt = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("Dropped \(stamp) (\(attempt)).\(ext)")
            attempt += 1
        }

        do {
            try data.write(to: url)
            return url
        } catch {
            Log.shelf.error("Could not stage a dropped image: \(error.localizedDescription)")
            return nil
        }
    }

    /// Dropped data is written here rather than into the user's own folders, so
    /// the shelf never litters the Desktop with things they only parked briefly.
    private static var stagingDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Bondex Notch/Dropped", isDirectory: true)
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()
}
