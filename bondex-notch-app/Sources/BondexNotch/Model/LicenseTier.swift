import Foundation

/// The app has one feature set. A user can access it during the 24-hour trial
/// or after activating a purchased licence.
enum LicenseAccessState: Equatable {
    case trial(expiresAt: Date)
    case licensed
    case expired

    var displayName: String {
        switch self {
        case .trial: return "24-hour trial"
        case .licensed: return "Licensed"
        case .expired: return "Trial expired"
        }
    }

    var canUseApp: Bool {
        switch self {
        case .trial, .licensed: return true
        case .expired: return false
        }
    }
}

/// Offline license check.
///
/// NOTE: This is deliberately a *format* check, not real DRM. It exists so the
/// licence activation flow is wired end to end; before shipping paid builds,
/// replace `validate` with a server-issued signed receipt so keys cannot be
/// forged. StoreKit is not required for direct website distribution.
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
