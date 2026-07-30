import SwiftUI

/// Motion curves for the panel.
///
/// The expand/collapse curve is the identity of the product, so it is defined
/// in exactly one place and scaled by the user's animation-speed preference.
enum Motion {

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
            case .snappy: return 0.7
            }
        }
    }

    /// The main open/close spring. Slightly over-damped so the panel settles
    /// without visible ringing at the top edge of the display.
    static func panel(_ speed: Speed) -> Animation {
        .spring(response: 0.36 * speed.factor, dampingFraction: 0.78, blendDuration: 0.1)
    }

    /// Content crossfades inside the panel, kept faster than the panel itself
    /// so text never appears to lag behind the frame.
    static func content(_ speed: Speed) -> Animation {
        .spring(response: 0.26 * speed.factor, dampingFraction: 0.86)
    }

    static func value(_ speed: Speed) -> Animation {
        .easeInOut(duration: 0.45 * speed.factor)
    }
}
