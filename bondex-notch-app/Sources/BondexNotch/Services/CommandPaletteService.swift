import Combine
import Foundation

struct CommandPaletteCommand: Identifiable, Equatable {
    enum Action: Equatable {
        case createCapture
        case toggleFocus
        case customAction(UUID)
        case clipboard(UUID)
        case capture(UUID)
        case shelf(UUID)
        case showWidget(NotchTab)
        case activateProfile(UUID)
        case automaticProfiles
        case disableProfiles
        case openSettings(SettingsPage)
    }

    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let category: String
    let keywords: [String]
    let priority: Int
    let action: Action

    static func search(
        _ query: String,
        in commands: [CommandPaletteCommand],
        limit: Int = 6
    ) -> [CommandPaletteCommand] {
        let terms = query
            .split(whereSeparator: \Character.isWhitespace)
            .map { String($0).localizedLowercase }

        return commands
            .compactMap { command -> (CommandPaletteCommand, Int)? in
                guard !terms.isEmpty else { return (command, -command.priority) }

                let title = command.title.localizedLowercase
                let subtitle = command.subtitle.localizedLowercase
                let category = command.category.localizedLowercase
                let keywords = command.keywords.map(\.localizedLowercase)
                var score = -command.priority

                for term in terms {
                    if title == term {
                        score += 140
                    } else if title.hasPrefix(term) {
                        score += 100
                    } else if title.contains(term) {
                        score += 72
                    } else if subtitle.contains(term) {
                        score += 42
                    } else if category.contains(term) || keywords.contains(where: { $0.contains(term) }) {
                        score += 28
                    } else {
                        return nil
                    }
                }
                return (command, score)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.0.priority != $1.0.priority { return $0.0.priority < $1.0.priority }
                return $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending
            }
            .prefix(max(limit, 0))
            .map(\.0)
    }
}

@MainActor
final class CommandPaletteService: ObservableObject {
    @Published private(set) var isPresented = false
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            selectedIndex = 0
        }
    }
    @Published private(set) var selectedIndex = 0

    func present() {
        query = ""
        selectedIndex = 0
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        query = ""
        selectedIndex = 0
    }

    func moveSelection(by offset: Int, resultCount: Int) {
        guard resultCount > 0 else {
            selectedIndex = 0
            return
        }
        let destination = (selectedIndex + offset) % resultCount
        selectedIndex = destination >= 0 ? destination : destination + resultCount
    }

    func select(_ index: Int, resultCount: Int) {
        guard resultCount > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(index, 0), resultCount - 1)
    }
}
