import AppKit
import Combine
import Foundation

@MainActor
final class SmartProfileService: ObservableObject {
    @Published private(set) var context: SmartProfileContext

    private let settings: SettingsStore
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsStore) {
        self.settings = settings
        self.context = SmartProfileContext(
            activeApplicationBundleIdentifier: NSWorkspace.shared.frontmostApplication?
                .bundleIdentifier,
            hour: Calendar.current.component(.hour, from: Date()),
            isPluggedIn: nil,
            displayCount: NSScreen.screens.count,
            meetingIsActive: false
        )
    }

    var activeProfile: NotchProfile? { settings.activeProfile }

    var needsPowerContext: Bool {
        settings.preferences.smartProfileMode == .automatic
            && settings.preferences.notchProfiles.contains { $0.rules.power != .any }
    }

    var needsMeetingContext: Bool {
        settings.preferences.smartProfileMode == .automatic
            && settings.preferences.notchProfiles.contains { $0.rules.duringMeeting }
    }

    func start() {
        guard cancellables.isEmpty else {
            refresh()
            return
        }

        let workspace = NSWorkspace.shared
        workspace.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                self?.context.activeApplicationBundleIdentifier = application?.bundleIdentifier
                self?.refresh()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.context.displayCount = NSScreen.screens.count
                self?.refresh()
            }
            .store(in: &cancellables)

        settings.$preferences
            .removeDuplicates()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            onMainActor { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
        settings.setActiveProfile(nil)
    }

    func updatePower(_ snapshot: SystemSnapshot) {
        let pluggedIn = snapshot.batteryLevel == nil ? nil : snapshot.isPluggedIn
        guard context.isPluggedIn != pluggedIn else { return }
        context.isPluggedIn = pluggedIn
        refresh()
    }

    func updateMeeting(_ meeting: UpcomingMeeting?) {
        let isActive = meeting?.startsSoon() ?? false
        guard context.meetingIsActive != isActive else { return }
        context.meetingIsActive = isActive
        refresh()
    }

    func activate(_ profileID: UUID) {
        guard settings.preferences.notchProfiles.contains(where: { $0.id == profileID }) else {
            return
        }
        settings.preferences.selectedProfileID = profileID
        settings.preferences.smartProfileMode = .manual
    }

    func useAutomaticMode() {
        settings.preferences.smartProfileMode = .automatic
    }

    func turnOff() {
        settings.preferences.smartProfileMode = .off
    }

    func refresh(at date: Date = Date()) {
        context.hour = Calendar.current.component(.hour, from: date)
        let profile: NotchProfile?
        switch settings.preferences.smartProfileMode {
        case .off:
            profile = nil
        case .manual:
            profile = settings.preferences.notchProfiles.first {
                $0.id == settings.preferences.selectedProfileID
            }
        case .automatic:
            profile = Self.matchingProfile(
                in: settings.preferences.notchProfiles,
                context: context
            )
        }
        settings.setActiveProfile(profile)
    }

    nonisolated static func matchingProfile(
        in profiles: [NotchProfile],
        context: SmartProfileContext
    ) -> NotchProfile? {
        profiles.first { $0.rules.matches(context) }
    }
}
