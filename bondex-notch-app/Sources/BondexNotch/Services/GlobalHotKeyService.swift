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

enum QuickCaptureShortcut: String, CaseIterable, Codable, Identifiable {
    case controlOptionC
    case commandShiftN
    case controlShiftSpace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .controlOptionC: return "⌃⌥ C"
        case .commandShiftN: return "⇧⌘ N"
        case .controlShiftSpace: return "⌃⇧ Space"
        }
    }

    fileprivate var keyCode: UInt32 {
        switch self {
        case .controlOptionC: return UInt32(kVK_ANSI_C)
        case .commandShiftN: return UInt32(kVK_ANSI_N)
        case .controlShiftSpace: return UInt32(kVK_Space)
        }
    }

    fileprivate var modifiers: UInt32 {
        switch self {
        case .controlOptionC: return UInt32(controlKey | optionKey)
        case .commandShiftN: return UInt32(cmdKey | shiftKey)
        case .controlShiftSpace: return UInt32(controlKey | shiftKey)
        }
    }
}

/// Registers a system-wide shortcut without Input Monitoring permission.
/// Carbon's hot-key API remains the appropriate macOS API for a background
/// menu-bar agent because it registers one explicit chord rather than reading
/// arbitrary keyboard input.
@MainActor
final class GlobalHotKeyService {
    enum Action: Equatable {
        case panel
        case quickCapture
    }

    var onPress: (() -> Void)?
    var onQuickCapture: (() -> Void)?

    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    func start(
        shortcut: GlobalShortcut?,
        quickCaptureShortcut: QuickCaptureShortcut? = nil
    ) {
        stop()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            Log.app.error("Could not install global shortcut handler: \(handlerStatus)")
            eventHandler = nil
            return
        }

        if let shortcut {
            register(
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers,
                id: Self.panelHotKeyID,
                name: "panel"
            )
        }
        if let quickCaptureShortcut {
            register(
                keyCode: quickCaptureShortcut.keyCode,
                modifiers: quickCaptureShortcut.modifiers,
                id: Self.quickCaptureHotKeyID,
                name: "Quick Capture"
            )
        }

        if hotKeys.isEmpty, let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, name: String) {
        let identifier = EventHotKeyID(signature: Self.signature, id: id)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            hotKeys.append(reference)
        } else {
            Log.app.error("Could not register \(name) shortcut: \(status)")
        }
    }

    func stop() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeys.removeAll()
        eventHandler = nil
    }

    private func pressed(id: UInt32) {
        switch Self.action(forHotKeyID: id) {
        case .panel: onPress?()
        case .quickCapture: onQuickCapture?()
        case nil: break
        }
    }

    static func action(forHotKeyID id: UInt32) -> Action? {
        switch id {
        case panelHotKeyID: return .panel
        case quickCaptureHotKeyID: return .quickCapture
        default: return nil
        }
    }

    private static let signature: OSType = 0x424E4458 // "BNDX"
    private static let panelHotKeyID: UInt32 = 1
    private static let quickCaptureHotKeyID: UInt32 = 2

    private static let eventCallback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard status == noErr else { return status }

        let service = Unmanaged<GlobalHotKeyService>
            .fromOpaque(userData)
            .takeUnretainedValue()
        DispatchQueue.main.async { service.pressed(id: identifier.id) }
        return noErr
    }
}
