import AppKit
import Carbon
import SwiftUI

/// Records a global shortcut: click, press the combination, done.
///
/// Esc cancels, and clicking elsewhere cancels. A combination without ⌘, ⌃ or
/// ⌥, one every app relies on (⌘Q, ⌘C…), or one another Bondex shortcut
/// already uses is refused with the reason, rather than saved and left to
/// misbehave.
struct ShortcutRecorder: View {
    @Binding var hotKey: HotKey
    let defaultValue: HotKey
    /// The other Bondex shortcuts, by name, which this one must not repeat.
    let others: [(name: String, hotKey: HotKey)]
    /// macOS would not register this one — another app holds it.
    let isUnavailable: Bool
    let onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var problem: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 6) {
                Button(action: toggleRecording) {
                    Text(isRecording ? "Type a shortcut…" : hotKey.displayName)
                        .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                        .frame(minWidth: 118)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : nil)
                .help(isRecording ? "Press the new shortcut, or Esc to cancel" : "Click to record a new shortcut")
                .accessibilityLabel("Shortcut \(hotKey.displayName)")
                .accessibilityHint("Activate, then press a new key combination")

                if hotKey != defaultValue, !isRecording {
                    Button {
                        problem = nil
                        hotKey = defaultValue
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to \(defaultValue.displayName)")
                    .accessibilityLabel("Reset shortcut to \(defaultValue.displayName)")
                }
            }

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isUnavailable, !isRecording {
                Text("In use by another app — pick another")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { finish() }
    }

    private func toggleRecording() {
        isRecording ? finish() : begin()
    }

    private func begin() {
        problem = nil
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            guard event.type == .keyDown else {
                // A click anywhere else gives up on recording.
                finish()
                return event
            }
            record(event)
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape),
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            finish()
            return
        }
        switch HotKey.recorded(keyCode: event.keyCode, flags: event.modifierFlags) {
        case .failure(.needsModifier):
            problem = "Use ⌘, ⌃ or ⌥ with the key"
        case .failure(.reserved):
            problem = "That shortcut belongs to every app"
        case .success(let recorded):
            if let clash = others.first(where: { $0.hotKey == recorded }) {
                problem = "Already used for \(clash.name)"
            } else {
                problem = nil
                hotKey = recorded
                finish()
            }
        }
    }

    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        onRecordingChange(false)
    }
}
