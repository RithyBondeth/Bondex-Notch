import AppKit
import AudioToolbox
import CoreAudio
import IOKit.graphics
import IOKit.hidsystem

/// Watches the Mac's hardware-control keys and turns them into compact notch
/// feedback. It observes rather than consumes the events, so macOS remains the
/// authority that actually changes volume and brightness.
@MainActor
final class SystemHUDService {

    var onPresentation: ((SystemHUDPresentation) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollTimer: Timer?
    private var lastVolume = 0.5
    private var lastMuted = false
    private var lastDisplayBrightness = 0.5
    private var lastKeyboardBrightness = 0.5
    private var observedVolume: (level: Double, isMuted: Bool)?
    private var observedDisplayBrightness: Double?
    private var previousBattery: SystemSnapshot?

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            onMainActor { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            self?.handle(event)
            return event
        }

        // Global media-key monitors may be withheld by macOS when Input
        // Monitoring has not been granted. Sampling the authoritative values is
        // permission-free and also catches Control Center and external-keyboard
        // changes. The first pass is only a baseline, never a launch banner.
        sampleControls(announceChanges: false)
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            onMainActor { self?.sampleControls(announceChanges: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
        observedVolume = nil
        observedDisplayBrightness = nil
        previousBattery = nil
    }

    private func sampleControls(announceChanges: Bool) {
        if let volume = Self.readVolume() {
            if announceChanges, let previous = observedVolume,
               abs(volume.level - previous.level) >= 0.005
                || volume.isMuted != previous.isMuted {
                present(.init(
                    kind: .volume,
                    level: volume.level,
                    isMuted: volume.isMuted
                ))
            }
            observedVolume = volume
            lastVolume = volume.level
            lastMuted = volume.isMuted
        }

        if let brightness = Self.readDisplayBrightness() {
            if announceChanges, let previous = observedDisplayBrightness,
               abs(brightness - previous) >= 0.005 {
                present(.init(kind: .brightness, level: brightness))
            }
            observedDisplayBrightness = brightness
            lastDisplayBrightness = brightness
        }
    }

    /// Called by the existing metrics sampler. The first sample establishes a
    /// baseline; subsequent power-source transitions deserve feedback, ordinary
    /// one-percent discharge steps do not.
    func updateBattery(_ snapshot: SystemSnapshot) {
        defer { previousBattery = snapshot }
        guard let previous = previousBattery,
              let level = snapshot.batteryLevel,
              previous.batteryLevel != nil else { return }

        guard snapshot.isPluggedIn != previous.isPluggedIn
                || snapshot.isCharging != previous.isCharging else { return }

        let detail: String
        if snapshot.isCharging {
            detail = "Charging"
        } else if snapshot.isPluggedIn {
            detail = "Power connected"
        } else {
            detail = "On battery"
        }
        present(.init(kind: .battery, level: level, detail: detail))
    }

    private func handle(_ event: NSEvent) {
        // 8 is NX_SUBTYPE_AUX_CONTROL_BUTTONS. The lower word contains the key
        // state; 0xA is key down (including key-repeat), 0xB is key up.
        guard event.subtype.rawValue == 8 else { return }
        let data = event.data1
        let keyType = Int32((data & 0xFFFF_0000) >> 16)
        let keyState = Int((data & 0x0000_FF00) >> 8)
        guard keyState == 0xA else { return }

        switch keyType {
        case NX_KEYTYPE_SOUND_UP:
            showVolume(fallbackDelta: 1.0 / 16.0)
        case NX_KEYTYPE_SOUND_DOWN:
            showVolume(fallbackDelta: -1.0 / 16.0)
        case NX_KEYTYPE_MUTE:
            showVolume(fallbackDelta: 0)
        case NX_KEYTYPE_BRIGHTNESS_UP:
            showDisplayBrightness(delta: 1.0 / 16.0)
        case NX_KEYTYPE_BRIGHTNESS_DOWN:
            showDisplayBrightness(delta: -1.0 / 16.0)
        case NX_KEYTYPE_ILLUMINATION_UP:
            lastKeyboardBrightness = Self.clamp(lastKeyboardBrightness + 1.0 / 16.0)
            present(.init(kind: .keyboardBrightness, level: lastKeyboardBrightness))
        case NX_KEYTYPE_ILLUMINATION_DOWN:
            lastKeyboardBrightness = Self.clamp(lastKeyboardBrightness - 1.0 / 16.0)
            present(.init(kind: .keyboardBrightness, level: lastKeyboardBrightness))
        default:
            break
        }
    }

    private func showVolume(fallbackDelta: Double) {
        // The system handles the same event alongside us. Read just after it has
        // applied the change so the percentage matches Sound settings exactly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { [weak self] in
            guard let self else { return }
            let state = Self.readVolume()
            let level = state?.level ?? Self.clamp(self.lastVolume + fallbackDelta)
            let muted: Bool
            if let state {
                muted = state.isMuted
            } else if fallbackDelta == 0 {
                muted = !self.lastMuted
            } else {
                muted = false
            }
            self.lastVolume = level
            self.lastMuted = muted
            self.observedVolume = (level, muted)
            self.present(.init(
                kind: .volume,
                level: level,
                isMuted: muted
            ))
        }
    }

    private func showDisplayBrightness(delta: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { [weak self] in
            guard let self else { return }
            let level = Self.readDisplayBrightness()
                ?? Self.clamp(self.lastDisplayBrightness + delta)
            self.lastDisplayBrightness = level
            self.observedDisplayBrightness = level
            self.present(.init(kind: .brightness, level: level))
        }
    }

    private func present(_ presentation: SystemHUDPresentation) {
        onPresentation?(presentation)
    }

    static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    // MARK: Current system values

    private static func readVolume() -> (level: Double, isMuted: Bool)? {
        var device = AudioDeviceID(0)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddress,
            0, nil, &deviceSize, &device
        ) == noErr, device != 0 else { return nil }

        let level = readScalar(
            device: device,
            selector: kAudioDevicePropertyVolumeScalar
        )
        guard let level else { return nil }
        return (Double(level), readMute(device: device))
    }

    private static func readMute(device: AudioDeviceID) -> Bool {
        func value(element: AudioObjectPropertyElement) -> UInt32? {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(device, &address) else { return nil }
            var result = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(
                device, &address, 0, nil, &size, &result
            ) == noErr else { return nil }
            return result
        }

        return (value(element: kAudioObjectPropertyElementMain)
                ?? value(element: 1)
                ?? value(element: 2)
                ?? 0) != 0
    }

    /// Some aggregate/Bluetooth outputs expose volume only per channel, while
    /// built-in speakers expose a main element. Try both and average stereo.
    private static func readScalar(
        device: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> Float32? {
        func value(element: AudioObjectPropertyElement) -> Float32? {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(device, &address) else { return nil }
            var result = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(
                device, &address, 0, nil, &size, &result
            ) == noErr else { return nil }
            return result
        }

        if let main = value(element: kAudioObjectPropertyElementMain) { return main }
        let channels = [value(element: 1), value(element: 2)].compactMap { $0 }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Float32(channels.count)
    }

    private static func readDisplayBrightness() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            var value: Float = 0
            if IODisplayGetFloatParameter(
                service, 0, kIODisplayBrightnessKey as CFString, &value
            ) == KERN_SUCCESS {
                return clamp(Double(value))
            }
        }
        return nil
    }
}
