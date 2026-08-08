import CoreAudio
import CoreMediaIO
import Foundation

struct PrivacyActivityState: Equatable {
    var microphoneActive = false
    var cameraActive = false

    var isActive: Bool { microphoneActive || cameraActive }

    var label: String {
        switch (microphoneActive, cameraActive) {
        case (true, true): return "Camera & Microphone"
        case (true, false): return "Microphone"
        case (false, true): return "Camera"
        case (false, false): return "Privacy"
        }
    }

    var accessibilityValue: String {
        isActive ? "\(label) active" : "Camera and microphone inactive"
    }
}

/// Observes whether any audio-input or video-capture device is running.
/// CoreAudio and CoreMediaIO expose device activity without opening a stream,
/// so this never records content or asks for microphone/camera permission.
@MainActor
final class PrivacyActivityService: ObservableObject {
    @Published private(set) var state = PrivacyActivityState()

    typealias ActivityReader = () -> Bool

    private let readMicrophoneActivity: ActivityReader
    private let readCameraActivity: ActivityReader
    private var timer: Timer?

    init(
        readMicrophoneActivity: @escaping ActivityReader = PrivacyActivityService.isMicrophoneActive,
        readCameraActivity: @escaping ActivityReader = PrivacyActivityService.isCameraActive
    ) {
        self.readMicrophoneActivity = readMicrophoneActivity
        self.readCameraActivity = readCameraActivity
    }

    func start(interval: TimeInterval = 0.75) {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            onMainActor { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        state = PrivacyActivityState()
    }

    func refresh() {
        let next = PrivacyActivityState(
            microphoneActive: readMicrophoneActivity(),
            cameraActive: readCameraActivity()
        )
        if next != state { state = next }
    }

    func seedForPreview(_ state: PrivacyActivityState) {
        self.state = state
    }

    // MARK: Device activity

    nonisolated private static func isMicrophoneActive() -> Bool {
        audioDeviceIDs().contains { device in
            guard audioDeviceHasInput(device) else { return false }
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(
                device, &address, 0, nil, &size, &running
            )
            return status == noErr && running != 0
        }
    }

    nonisolated private static func audioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == noErr else { return [] }
        return devices
    }

    nonisolated private static func audioDeviceHasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr
            && size >= MemoryLayout<AudioStreamID>.size
    }

    nonisolated private static func isCameraActive() -> Bool {
        cameraDeviceIDs().contains { device in
            var address = CMIOObjectPropertyAddress(
                mSelector: UInt32(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
                mElement: UInt32(kCMIOObjectPropertyElementMain)
            )
            var running: UInt32 = 0
            let size = UInt32(MemoryLayout<UInt32>.size)
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                device, &address, 0, nil, size, &used, &running
            )
            return status == noErr && used == size && running != 0
        }
    }

    nonisolated private static func cameraDeviceIDs() -> [CMIODeviceID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: UInt32(kCMIOHardwarePropertyDevices),
            mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
            mElement: UInt32(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<CMIODeviceID>.size
        var devices = [CMIODeviceID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices
        ) == noErr else { return [] }
        return Array(devices.prefix(Int(used) / MemoryLayout<CMIODeviceID>.size))
    }
}
