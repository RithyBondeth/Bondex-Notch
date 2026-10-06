import AppKit
import Combine
import Sparkle

/// In-app updates, through Sparkle.
///
/// Version 1.0.0 had no way to say a newer one existed, so everyone who
/// downloaded it stayed on it. Sparkle checks an appcast published with each
/// GitHub release, and verifies every download against the EdDSA public key in
/// Info.plist, which is what lets it work without an Apple Developer ID.
///
/// Nothing is checked until the person agrees: with no `SUEnableAutomaticChecks`
/// in Info.plist, Sparkle asks on the second launch, and the answer can be
/// changed in Settings. A check is one request for the appcast; the system
/// profile Sparkle can send is left off.
///
/// Only a release build carries `SUFeedURL` and `SUPublicEDKey`. A debug build,
/// the tests and the preview tool have neither, so the updater never starts
/// there — a developer's own build must not replace itself with a release.
@MainActor
final class UpdateService: NSObject, ObservableObject {

    /// Whether this build can update itself at all.
    let isConfigured: Bool

    @Published private(set) var canCheck = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var lastCheck: Date?
    /// A version a scheduled check found, while it waits for the person to
    /// look. A menu-bar app has no window to raise, so the update is offered
    /// in the menu rather than thrown up over whatever they are doing.
    @Published private(set) var waitingVersion: String?

    private var controller: SPUStandardUpdaterController?
    private var observations: [AnyCancellable] = []

    init(bundle: Bundle = .main) {
        isConfigured = Self.isConfigured(bundle.infoDictionary ?? [:])
        super.init()
    }

    /// Both keys present and non-empty. A feed without a key would be refused
    /// by Sparkle at the first download; better never to offer one.
    nonisolated static func isConfigured(_ info: [String: Any]) -> Bool {
        let feed = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let key = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return URL(string: feed)?.scheme == "https" && !key.isEmpty
    }

    func start() {
        guard isConfigured, controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        self.controller = controller
        let updater = controller.updater
        updater.sendsSystemProfile = false

        do {
            try updater.start()
        } catch {
            Log.app.error("Updater did not start: \(error.localizedDescription)")
            self.controller = nil
            return
        }

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheck = $0 }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.automaticallyChecks = $0 }
            .store(in: &observations)
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastCheck = $0 }
            .store(in: &observations)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    /// A user-initiated check, which always shows its result — including
    /// "you're up to date" — and brings a waiting update into focus.
    func checkNow() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

extension UpdateService: SPUStandardUserDriverDelegate {

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Shows a scheduled update straight away only when Sparkle judges the
    /// moment right (just launched, or back from idle); otherwise it waits in
    /// the menu.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        let isWaiting = !handleShowingUpdate && !state.userInitiated
        MainActor.assumeIsolated {
            if isWaiting { waitingVersion = version }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { waitingVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { waitingVersion = nil }
    }
}
