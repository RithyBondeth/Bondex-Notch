import Foundation

enum LicenseTier: String, Codable {
    case free
    case pro

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        }
    }
}

/// Features that the proposal splits across the Free and Pro tiers.
///
/// Only add a case once the feature actually exists — this list is rendered
/// verbatim as "Pro includes" in Settings, so an aspirational entry reads as a
/// promise the app does not keep.
enum ProFeature: String, CaseIterable, Identifiable {
    case fileActivity
    case shelf
    case customThemes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fileActivity: return "File Activity"
        case .shelf: return "Drop Shelf"
        case .customThemes: return "Custom Themes"
        }
    }
}

/// Offline license check.
///
/// NOTE: This is deliberately a *format* check, not real DRM. It exists so the
/// Free/Pro split in the proposal is wired end to end; before shipping paid
/// builds, replace `validate` with a server-issued signed receipt (or
/// StoreKit 2 `Transaction.currentEntitlements`) so keys cannot be forged.
enum LicenseValidator {
    static let keyFormat = "BNDX-XXXX-XXXX-XXXX"

    static func validate(_ rawKey: String) -> Bool {
        let key = rawKey.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = key.split(separator: "-")
        guard groups.count == 4, groups[0] == "BNDX" else { return false }
        guard groups.dropFirst().allSatisfy({ $0.count == 4 && $0.allSatisfy(\.isHexDigit) }) else {
            return false
        }
        // Last group is a checksum over the two payload groups.
        let payload = Array(groups[1]) + Array(groups[2])
        let sum = payload.reduce(0) { $0 &+ Int($1.hexDigitValue ?? 0) }
        let expected = String(format: "%04X", (sum &* 2654) & 0xFFFF)
        return String(groups[3]) == expected
    }

    /// Used by the test/demo path and by whatever issues real keys later.
    static func makeKey(payload: String) -> String? {
        let upper = payload.uppercased()
        guard upper.count == 8, upper.allSatisfy(\.isHexDigit) else { return nil }
        let sum = upper.reduce(0) { $0 &+ Int($1.hexDigitValue ?? 0) }
        let checksum = String(format: "%04X", (sum &* 2654) & 0xFFFF)
        let a = upper.prefix(4), b = upper.dropFirst(4)
        return "BNDX-\(a)-\(b)-\(checksum)"
    }
}
