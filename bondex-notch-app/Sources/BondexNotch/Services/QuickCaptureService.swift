import AppKit
import Foundation

struct QuickCaptureItem: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var createdAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.isPinned = isPinned
    }

    var title: String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var isLink: Bool {
        URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme != nil
    }

    var detail: String {
        isLink ? "Link" : createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty || text.localizedCaseInsensitiveContains(needle)
    }
}

/// A small, persistent inbox for text and links captured from the notch.
/// Data stays in the app's local UserDefaults domain and is never transmitted.
@MainActor
final class QuickCaptureService: ObservableObject {
    @Published private(set) var items: [QuickCaptureItem]
    @Published var draft = ""
    @Published private(set) var focusRequest = 0

    private static let defaultsKey = "com.bondex.notch.quick-captures"
    private static let maximumLength = 10_000

    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private let capacity: Int
    private var wantsComposerFocus = false

    init(
        defaults: UserDefaults = .standard,
        pasteboard: NSPasteboard = .general,
        capacity: Int = 100
    ) {
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.capacity = max(capacity, 1)
        self.items = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([QuickCaptureItem].self, from: $0) }
            ?? []
        sortItems()
        trimToCapacity()
    }

    var isEmpty: Bool { items.isEmpty }
    var canSaveDraft: Bool { normalized(draft) != nil }

    func begin() {
        wantsComposerFocus = true
        focusRequest &+= 1
    }

    func consumeFocusRequest() -> Bool {
        guard wantsComposerFocus else { return false }
        wantsComposerFocus = false
        return true
    }

    @discardableResult
    func saveDraft() -> Bool {
        guard let text = normalized(draft) else { return false }
        add(text)
        draft = ""
        begin()
        return true
    }

    func cancelDraft() {
        draft = ""
        wantsComposerFocus = false
    }

    @discardableResult
    func pasteFromClipboard() -> Bool {
        guard let value = pasteboard.string(forType: .string),
              let text = normalized(value) else { return false }
        draft = text
        begin()
        return true
    }

    func copy(_ item: QuickCaptureItem) {
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        touch(item.id)
    }

    func togglePinned(_ item: QuickCaptureItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        sortItems()
        persist()
    }

    func remove(_ item: QuickCaptureItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    func seedForPreview(_ samples: [QuickCaptureItem]) {
        items = samples
        sortItems()
        trimToCapacity()
    }

    private func add(_ text: String) {
        if let index = items.firstIndex(where: { $0.text == text }) {
            var existing = items.remove(at: index)
            existing.createdAt = Date()
            items.append(existing)
        } else {
            items.append(QuickCaptureItem(text: text))
        }
        sortItems()
        trimToCapacity()
        persist()
    }

    private func touch(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].createdAt = Date()
        sortItems()
        persist()
    }

    private func normalized(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= Self.maximumLength else { return nil }
        return text
    }

    private func sortItems() {
        items.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
    }

    private func trimToCapacity() {
        guard items.count > capacity else { return }
        items.removeLast(items.count - capacity)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
