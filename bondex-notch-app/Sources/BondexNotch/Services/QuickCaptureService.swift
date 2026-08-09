import AppKit
import Foundation

struct QuickCaptureItem: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var createdAt: Date
    var isPinned: Bool
    var enhancement: CaptureEnhancement?

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        enhancement: CaptureEnhancement? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.enhancement = enhancement
    }

    var title: String {
        if let title = enhancement?.title, !title.isEmpty { return title }
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var isLink: Bool {
        URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme != nil
    }

    var detail: String {
        if let summary = enhancement?.summary, !summary.isEmpty { return summary }
        return isLink ? "Link" : createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty
            || text.localizedCaseInsensitiveContains(needle)
            || enhancement?.title.localizedCaseInsensitiveContains(needle) == true
            || enhancement?.summary.localizedCaseInsensitiveContains(needle) == true
            || enhancement?.tags.contains(where: {
                $0.localizedCaseInsensitiveContains(needle)
            }) == true
    }
}

/// A small, persistent inbox for text and links captured from the notch.
/// Data stays in the app's local UserDefaults domain and is never transmitted.
@MainActor
final class QuickCaptureService: ObservableObject {
    @Published private(set) var items: [QuickCaptureItem]
    @Published var draft = "" {
        didSet {
            if draft != enhancedDraftText {
                draftEnhancement = nil
                enhancedDraftText = nil
            }
        }
    }
    @Published private(set) var draftEnhancement: CaptureEnhancement?
    @Published private(set) var focusRequest = 0

    private static let defaultsKey = "com.bondex.notch.quick-captures"
    private static let maximumLength = 10_000

    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private let capacity: Int
    private var wantsComposerFocus = false
    private var enhancedDraftText: String?

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
        add(text, enhancement: draftEnhancement)
        draft = ""
        draftEnhancement = nil
        enhancedDraftText = nil
        begin()
        return true
    }

    func applyEnhancement(_ enhancement: CaptureEnhancement) {
        guard normalized(draft) != nil else { return }
        draftEnhancement = enhancement
        enhancedDraftText = draft
    }

    /// Saves text supplied by a system integration such as App Intents without
    /// borrowing or clearing the user's in-progress composer draft.
    @discardableResult
    func capture(_ value: String) -> Bool {
        guard let text = normalized(value) else { return false }
        add(text)
        return true
    }

    func cancelDraft() {
        draft = ""
        draftEnhancement = nil
        enhancedDraftText = nil
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

    private func add(_ text: String, enhancement: CaptureEnhancement? = nil) {
        if let index = items.firstIndex(where: { $0.text == text }) {
            var existing = items.remove(at: index)
            existing.createdAt = Date()
            if let enhancement { existing.enhancement = enhancement }
            items.append(existing)
        } else {
            items.append(QuickCaptureItem(text: text, enhancement: enhancement))
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
