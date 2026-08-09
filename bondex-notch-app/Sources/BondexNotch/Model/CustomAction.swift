import Foundation

struct CustomAction: Codable, Equatable, Identifiable {
    enum Target: Codable, Equatable {
        case application(bundleIdentifier: String?, path: String)
        case appleShortcut(name: String)
        case toggleWidget(NotchTab)
    }

    var id = UUID()
    var title: String
    var target: Target

    var subtitle: String {
        switch target {
        case .application: return "Open app"
        case .appleShortcut: return "Run Shortcut"
        case .toggleWidget: return "Toggle widget"
        }
    }

    var systemImage: String {
        switch target {
        case .application: return "app.fill"
        case .appleShortcut: return "command"
        case let .toggleWidget(tab): return tab.systemImage
        }
    }
}
