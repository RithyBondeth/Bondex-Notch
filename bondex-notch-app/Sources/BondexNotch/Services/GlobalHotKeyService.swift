import Carbon
import Foundation

enum GlobalShortcut: String, CaseIterable, Codable, Identifiable {
    case controlOptionSpace
    case commandShiftSpace
    case controlOptionN

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .controlOptionSpace: return "⌃⌥ Space"
        case .commandShiftSpace: return "⇧⌘ Space"
        case .controlOptionN: return "⌃⌥ N"
        }
    }

    fileprivate var keyCode: UInt32 {
        switch self {
        case .controlOptionSpace, .commandShiftSpace: return UInt32(kVK_Space)
        case .controlOptionN: return UInt32(kVK_ANSI_N)
        }
    }

    fileprivate var modifiers: UInt32 {
        switch self {
        case .controlOptionSpace, .controlOptionN:
            return UInt32(controlKey | optionKey)
        case .commandShiftSpace:
            return UInt32(cmdKey | shiftKey)
        }
    }
}

/// Registers a system-wide shortcut without Input Monitoring permission.
/// Carbon's hot-key API remains the appropriate macOS API for a background
/// menu-bar agent because it registers one explicit chord rather than reading
/// arbitrary keyboard input.
@MainActor
final class GlobalHotKeyService {

    var onPress: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func start(shortcut: GlobalShortcut) {
        stop()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if status != noErr {
            Log.app.error("Could not register global shortcut: \(status)")
            stop()
        }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
    }

    private func pressed() {
        onPress?()
    }

    private static let signature: OSType = 0x424E4458 // "BNDX"

    private static let eventCallback: EventHandlerUPP = { _, _, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let service = Unmanaged<GlobalHotKeyService>
            .fromOpaque(userData)
            .takeUnretainedValue()
        DispatchQueue.main.async { service.pressed() }
        return noErr
    }
}
