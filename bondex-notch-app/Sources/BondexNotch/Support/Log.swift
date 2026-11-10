import Foundation
import OSLog

enum Log {
    private static let subsystem = "com.bondex.notch"

    static let window = Logger(subsystem: subsystem, category: "window")
    static let music = Logger(subsystem: subsystem, category: "music")
    static let system = Logger(subsystem: subsystem, category: "system")
    static let files = Logger(subsystem: subsystem, category: "files")
    static let shelf = Logger(subsystem: subsystem, category: "shelf")
    static let agent = Logger(subsystem: subsystem, category: "agent")
    static let app = Logger(subsystem: subsystem, category: "app")
}

extension Formatter {
    static let byteCount: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()
}

extension Int64 {
    var formattedBytes: String { Formatter.byteCount.string(fromByteCount: self) }
}

extension TimeInterval {
    /// `m:ss` clock formatting used by the music widget.
    var clockString: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
