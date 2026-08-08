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
/// Finder URLs are held in place. Image-only drops are materialized in the
/// app's temporary directory and deleted when their shelf item is removed.
@MainActor
final class ShelfService: ObservableObject {

    @Published private(set) var items: [ShelfItem] = []

    /// Finder files arrive as file URLs. The floating thumbnail shown after a
    /// macOS screenshot is different: it advertises only image data, so both
    /// representations have to be accepted at the drop boundary.
    static let acceptedDropTypes: [UTType] = [.fileURL, .image]

    private let events: EventCenter
    private let maxItems = 20

    private static var temporaryDropDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Bondex Notch Shelf", isDirectory: true)
    }

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
        if items.count > maxItems {
            let overflow = items.suffix(from: maxItems)
            overflow.forEach { removeTemporaryCopy(at: $0.url) }
            items.removeLast(items.count - maxItems)
        }

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
        removeTemporaryCopy(at: item.url)
    }

    func clear() {
        items.forEach { removeTemporaryCopy(at: $0.url) }
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
    /// thumbnail) into a temporary file so the rest of the shelf can keep its
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
        let directory = temporaryDropDirectory
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

    private func removeTemporaryCopy(at url: URL) {
        guard Self.isTemporaryCopy(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func isTemporaryCopy(_ url: URL) -> Bool {
        let directory = temporaryDropDirectory.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate.hasPrefix(directory + "/")
    }
}
