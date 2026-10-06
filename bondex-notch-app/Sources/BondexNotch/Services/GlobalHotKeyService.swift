import Carbon
import Foundation
import AppKit

/// A global keyboard shortcut: one key and its modifiers, in Carbon's terms,
/// since that is what `RegisterEventHotKey` takes.
///
/// Replaces three enums of three presets each. Anything a person can press
/// with ⌘, ⌃ or ⌥ — or a function key on its own — can be recorded in
/// Settings. Decoding still accepts the old enum names, so a stored
/// `"controlOptionSpace"` comes back as ⌃⌥ Space.
struct HotKey: Equatable, Hashable, Codable {
    let keyCode: UInt32
    /// Carbon modifier flags: `cmdKey`, `optionKey`, `controlKey`, `shiftKey`.
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // MARK: Presets

    static let controlOptionSpace = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    static let commandShiftSpace = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))
    static let controlOptionN = HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey))
    static let controlOptionC = HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey))
    static let commandShiftN = HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | shiftKey))
    static let controlShiftSpace = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | shiftKey))
    static let controlOptionP = HotKey(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey))
    static let commandShiftP = HotKey(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey))
    static let controlOptionReturn = HotKey(keyCode: UInt32(kVK_Return), modifiers: UInt32(controlKey | optionKey))

    /// The names the presets were stored under before shortcuts could be
    /// recorded.
    private static let legacyNames: [String: HotKey] = [
        "controlOptionSpace": .controlOptionSpace,
        "commandShiftSpace": .commandShiftSpace,
        "controlOptionN": .controlOptionN,
        "controlOptionC": .controlOptionC,
        "commandShiftN": .commandShiftN,
        "controlShiftSpace": .controlShiftSpace,
        "controlOptionP": .controlOptionP,
        "commandShiftP": .commandShiftP,
        "controlOptionReturn": .controlOptionReturn
    ]

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers }

    init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            guard let preset = Self.legacyNames[name] else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown shortcut \(name)"
                ))
            }
            self = preset
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt32.self, forKey: .keyCode)
        modifiers = try container.decode(UInt32.self, forKey: .modifiers)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
    }

    // MARK: Recording

    /// Why a pressed combination cannot be a global shortcut.
    enum Problem: Error, Equatable {
        case needsModifier
        case reserved
    }

    /// The shortcut a key press describes, if it can be one.
    static func recorded(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Result<HotKey, Problem> {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let key = HotKey(keyCode: UInt32(keyCode), modifiers: modifiers)

        // ⌘Q, ⌘W, ⌘Tab and friends belong to every app, and a global
        // registration would take them away from all of them.
        if Self.reservedCombinations.contains(key) { return .failure(.reserved) }
        // Shift alone changes what a key types; taking ⇧A globally would stop
        // everyone typing a capital A. Function keys are the exception.
        let strong = UInt32(cmdKey | optionKey | controlKey)
        guard modifiers & strong != 0 || Self.functionKeys.contains(Int(keyCode)) else {
            return .failure(.needsModifier)
        }
        return .success(key)
    }

    private static let reservedCombinations: Set<HotKey> = [
        HotKey(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey)),
        HotKey(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(cmdKey)),
        HotKey(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey)),
        HotKey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey)),
        HotKey(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey)),
        HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey)),
        HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey)),
        HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey)),
        HotKey(keyCode: UInt32(kVK_ANSI_X), modifiers: UInt32(cmdKey)),
        HotKey(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(cmdKey)),
        HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey))
    ]

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ]

    // MARK: Display

    /// "⌃⌥ Space": modifiers in the order macOS menus use, then the key.
    var displayName: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols.isEmpty ? keyName : "\(symbols) \(keyName)"
    }

    var keyName: String {
        if let named = Self.namedKeys[Int(keyCode)] { return named }
        return Self.typedCharacter(for: keyCode) ?? "Key \(keyCode)"
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
        kVK_ForwardDelete: "⌦", kVK_Escape: "Esc", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "Home", kVK_End: "End",
        kVK_PageUp: "Page Up", kVK_PageDown: "Page Down", kVK_ANSI_KeypadEnter: "Enter",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

    /// What the key types on the current keyboard layout, so a recorded
    /// shortcut is labelled the way the user's keyboard is printed — "Z" on a
    /// German keyboard where a US one has "Y".
    private static func typedCharacter(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys, characters.count, &length, &characters
            )
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: characters, count: length)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text.uppercased()
        }
    }
}


/// Registers a system-wide shortcut without Input Monitoring permission.
/// Carbon's hot-key API remains the appropriate macOS API for a background
/// menu-bar agent because it registers one explicit chord rather than reading
/// arbitrary keyboard input.
@MainActor
final class GlobalHotKeyService: ObservableObject {
    enum Action: Equatable, Hashable {
        case panel
        case quickCapture
        case commandPalette
    }

    var onPress: (() -> Void)?
    var onQuickCapture: (() -> Void)?
    var onCommandPalette: (() -> Void)?

    /// Shortcuts macOS refused to register — almost always because another
    /// app already holds the same combination. Settings says so beside the
    /// shortcut, where it used to fail with only a log line.
    @Published private(set) var unavailable: Set<Action> = []

    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    func start(
        shortcut: HotKey?,
        quickCaptureShortcut: HotKey? = nil,
        commandPaletteShortcut: HotKey? = nil
    ) {
        stop()
        var failed: Set<Action> = []
        defer { unavailable = failed }

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

        for (hotKey, action, id) in [
            (shortcut, Action.panel, Self.panelHotKeyID),
            (quickCaptureShortcut, .quickCapture, Self.quickCaptureHotKeyID),
            (commandPaletteShortcut, .commandPalette, Self.commandPaletteHotKeyID)
        ] {
            guard let hotKey else { continue }
            if !register(keyCode: hotKey.keyCode, modifiers: hotKey.modifiers, id: id, name: "\(action)") {
                failed.insert(action)
            }
        }

        if hotKeys.isEmpty, let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    @discardableResult
    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, name: String) -> Bool {
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
            return true
        }
        Log.app.error("Could not register \(name) shortcut: \(status)")
        return false
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
        case .commandPalette: onCommandPalette?()
        case nil: break
        }
    }

    static func action(forHotKeyID id: UInt32) -> Action? {
        switch id {
        case panelHotKeyID: return .panel
        case quickCaptureHotKeyID: return .quickCapture
        case commandPaletteHotKeyID: return .commandPalette
        default: return nil
        }
    }

    private static let signature: OSType = 0x424E4458 // "BNDX"
    private static let panelHotKeyID: UInt32 = 1
    private static let quickCaptureHotKeyID: UInt32 = 2
    private static let commandPaletteHotKeyID: UInt32 = 3

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
