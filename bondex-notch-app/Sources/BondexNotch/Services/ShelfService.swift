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

    /// Resolves the file URLs out of a drop. Returns on the main actor once
    /// every provider has reported.
    func resolve(providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            continuation.resume(returning: url)
                        }
                    }
                }
            }
            var urls: [URL] = []
            for await url in group {
                if let url { urls.append(url) }
            }
            return urls
        }
    }
}
