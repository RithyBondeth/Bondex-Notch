import AppKit
import SwiftUI

/// Motion curves for the panel.
///
/// The expand/collapse curve is the identity of the product, so it is defined in
/// exactly one place and scaled by the user's animation-speed preference.
///
/// These use SwiftUI's `duration`/`bounce` spring form rather than
/// `response`/`dampingFraction`: `duration` is the perceptual settling time, so
/// scaling it by the speed factor changes how fast the panel feels without also
/// changing how much it overshoots.
enum Motion {

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    enum Speed: String, CaseIterable, Codable, Identifiable {
        case calm
        case standard
        case snappy

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .calm: return "Calm"
            case .standard: return "Standard"
            case .snappy: return "Snappy"
            }
        }

        var factor: Double {
            switch self {
            case .calm: return 1.35
            case .standard: return 1.0
            case .snappy: return 0.72
            }
        }
    }

    /// The main open/close spring. A small amount of bounce is what makes the
    /// panel read as a physical thing sliding out of the notch; more than this
    /// and the fillets visibly wobble against the top edge of the display.
    static func panel(_ speed: Speed) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.12) }
        return .spring(duration: 0.42 * speed.factor, bounce: 0.18)
    }

    /// Content crossfades inside the panel, faster than the panel itself so text
    /// never appears to lag behind the frame, and with almost no bounce so it
    /// does not wobble while it fades.
    static func content(_ speed: Speed) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.1) }
        return .spring(duration: 0.26 * speed.factor, bounce: 0.04)
    }

    /// Numbers and meters, which should glide rather than spring.
    static func value(_ speed: Speed) -> Animation {
        if reduceMotion { return .linear(duration: 0.08) }
        return .easeOut(duration: 0.4 * speed.factor)
    }

    /// Hover affordances inside the panel. Short and linear-ish, because these
    /// fire constantly as the pointer crosses controls.
    static let hover: Animation = .easeOut(duration: 0.12)
}
