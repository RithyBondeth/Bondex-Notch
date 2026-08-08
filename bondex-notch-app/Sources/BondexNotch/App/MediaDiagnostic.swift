import AppKit
import CoreServices
import Foundation

/// Runs the production media reader once and prints what it observed. This is a
/// support command rather than a second implementation, so it catches TCC,
/// AppleScript grammar, parsing and artwork-URL failures exactly as the panel
/// sees them.
enum MediaDiagnostic {

    @MainActor
    static func run() -> Int32 {
        let players = MediaApp.runningPlayers()
        let browsers = MediaApp.runningBrowsers()
        let appNames = (players + browsers).map(\.displayName).joined(separator: ", ")
        write("running=\(appNames.isEmpty ? "none" : appNames)\n")
        for app in players + browsers {
            let target = NSAppleEventDescriptor(bundleIdentifier: app.bundleIdentifier)
            let status = AEDeterminePermissionToAutomateTarget(
                target.aeDesc!, AEEventClass(typeWildCard), AEEventID(typeWildCard), false
            )
            write("\(app.displayName).automationStatus=\(status)\n")
        }

        let result = MediaReader().read(players: players, browsers: browsers)
        if let track = result.track {
            write("source=\(track.source.displayName)\n")
            write("title=\(track.title)\n")
            write("artist=\(track.artist)\n")
            write("playing=\(track.isPlaying)\n")
            write("artworkURL=\(track.artworkURL?.absoluteString ?? "none")\n")
            return 0
        }

        write("track=none\n")
        write("automationDenied=\(result.automationDenied)\n")
        write("blockedBrowser=\(result.blockedBrowser?.displayName ?? "none")\n")
        return 1
    }

    private static func write(_ value: String) {
        FileHandle.standardOutput.write(Data(value.utf8))
    }
}
