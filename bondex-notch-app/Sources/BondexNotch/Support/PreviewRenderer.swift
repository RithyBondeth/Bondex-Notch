import AppKit
import SwiftUI

/// Renders the panel's states to PNGs without needing a display.
///
/// The notch overlays the menu bar, which makes it awkward to capture with
/// normal screenshot tooling. Running
/// `Bondex Notch.app/Contents/MacOS/BondexNotch --render-previews <dir>`
/// writes one image per state so layout and spacing can be reviewed
/// (and diffed) directly.
@MainActor
enum PreviewRenderer {

    static func run(outputDirectory: String) -> Int32 {
        guard let screen = NSScreen.main else {
            FileHandle.standardError.write(Data("error: no screen available\n".utf8))
            return 1
        }

        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            return 1
        }

        // A throwaway defaults domain: rendering previews must never touch the
        // user's real preferences (it unlocks Pro to exercise every widget).
        let suiteName = "com.bondex.notch.preview"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let environment = AppEnvironment(screen: screen, defaults: defaults)
        seedSampleData(environment)

        // CPU usage is a delta between two samples, so the previews need at
        // least two ticks before the gauges mean anything.
        environment.metrics.start(interval: 0.6)
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        environment.metrics.stop()

        let snapshot = environment.metrics.snapshot
        print("""
        sampled: cpu=\(Int(snapshot.cpuUsage * 100))% \
        memory=\(Int64(snapshot.memoryUsed).formattedBytes)/\
        \(Int64(snapshot.memoryTotal).formattedBytes) \
        battery=\(snapshot.batteryLevel.map { "\(Int($0 * 100))%" } ?? "none")
        """)

        // Seed playback before rendering anything: the media row and the music
        // player are part of what these shots exist to review, and on a machine
        // with nothing playing they would all render as the empty state.
        let playing = NowPlaying(
            source: .dia,
            title: "BIGEGOAT vs AURORA! GOTF Watch Party Day 5",
            artist: "Mirko",
            album: "YouTube",
            isPlaying: true,
            duration: 7_235,
            position: 2_884,
            artwork: sampleVideoArtwork()
        )

        var failures = 0

        // Home with nothing playing, before anything is seeded. The panel is sized
        // from its content, so this must come out visibly shorter than the same tab
        // with a media row — that difference is the whole point, and a fixed height
        // got one of the two wrong however it was tuned.
        environment.nowPlaying.seedForPreview(nil)
        environment.notch.tab = .home
        environment.notch.expand()
        if !render(environment, named: "expanded-home-idle", into: directory) { failures += 1 }

        environment.nowPlaying.seedForPreview(playing)

        let liveSample = LiveActivity(
            id: "release-build",
            title: "Building release",
            subtitle: "Running tests",
            progress: 0.72,
            startedAt: Date().addingTimeInterval(-84),
            updatedAt: Date(),
            state: .active,
            completionMessage: nil
        )

        for tab in NotchTab.allCases {
            if tab == .live { environment.liveActivities.seedForPreview([liveSample]) }
            environment.notch.tab = tab
            environment.notch.expand()
            if !render(environment, named: "expanded-\(tab.rawValue)", into: directory) {
                failures += 1
            }
        }
        environment.liveActivities.seedForPreview([])

        environment.notch.collapse()
        if !render(environment, named: "collapsed", into: directory) { failures += 1 }

        // The peek is the state most sessions actually see, and it has two very
        // different shapes: a narrow strip while something is playing, and a wider
        // one while a banner is up. Both are worth reviewing.
        environment.notch.hasLiveActivity = true
        environment.notch.collapse()

        // Announce the track as well, which is what happens the moment playback is
        // first detected. This render is the regression guard for it: playback
        // must stay the narrow artwork-and-equaliser strip, never flash the title
        // as a banner first.
        environment.events.post(NotchEvent(
            kind: .music, title: "Weightless", subtitle: "Marconi Union"
        ))
        if !render(environment, named: "peek-playing", into: directory) { failures += 1 }

        environment.liveActivities.seedForPreview([liveSample])
        environment.notch.collapse()
        if !render(environment, named: "peek-live", into: directory) { failures += 1 }
        environment.liveActivities.seedForPreview([])

        environment.events.post(NotchEvent(
            kind: .download, title: "Xcode_26.xip", subtitle: "Download complete · 7.4 GB"
        ))
        if !render(environment, named: "peek-banner", into: directory) { failures += 1 }

        // Hardware-key feedback has its own compact meter layout and temporarily
        // outranks banners and playback, so keep a deterministic visual check.
        // Full volume exercises both rail insets; this is the boundary where a
        // fill without an inner gutter otherwise touches both track edges.
        environment.systemHUD.stop()
        environment.notch.show(systemHUD: .init(kind: .volume, level: 1.0))
        if !render(environment, named: "peek-volume", into: directory) { failures += 1 }

        environment.notch.show(systemHUD: .init(kind: .volume, level: 0.68, isMuted: true))
        if !render(environment, named: "peek-muted", into: directory) { failures += 1 }

        environment.notch.show(systemHUD: .init(kind: .brightness, level: 0.42))
        if !render(environment, named: "peek-brightness", into: directory) { failures += 1 }

        environment.notch.show(systemHUD: .init(
            kind: .battery, level: 0.76, detail: "Charging"
        ))
        if !render(environment, named: "peek-battery", into: directory) { failures += 1 }

        // The agent indicator, which on a machine with nothing running would
        // otherwise never appear in a preview — and it is the state the peek
        // spends its time in for anyone who uses a coding agent.
        // Expanding clears the banner still up from the shot above, which would
        // otherwise outrank the agent in the peek and render the same image twice.
        environment.notch.expand()
        environment.notch.workingAgentCount = 1
        environment.agents.seedForPreview([
            AgentActivity(
                kind: .claude,
                startedAt: Date().addingTimeInterval(-374),
                status: "Editing PeekView.swift"
            )
        ])
        environment.notch.collapse()
        if !render(environment, named: "peek-agent", into: directory) { failures += 1 }

        // Two agents at once, which is the case the strip has to grow for. Worth
        // a shot of its own: it is the one agent layout that cannot be checked by
        // running a single agent and looking at the notch.
        environment.notch.expand()
        environment.notch.workingAgentCount = 2
        environment.agents.seedForPreview([
            AgentActivity(
                kind: .claude,
                startedAt: Date().addingTimeInterval(-374),
                status: "Editing PeekView.swift"
            ),
            AgentActivity(
                kind: .codex,
                startedAt: Date().addingTimeInterval(-52),
                status: "Running tests"
            )
        ])
        environment.notch.collapse()
        if !render(environment, named: "peek-agents-two", into: directory) { failures += 1 }

        // The expanded detail those marks open into, with both agents listed.
        environment.notch.tab = .home
        environment.notch.expand()
        if !render(environment, named: "expanded-agents", into: directory) { failures += 1 }

        // Every mark Bondex ships, which is the only way to check the artwork:
        // the drawn marks are geometry, so a mistake in one is invisible until
        // it is rasterised, and no ordinary session has five agents running.
        // Also the overflow case — the card counts past three rather than
        // growing until Home clips.
        environment.agents.seedForPreview(AgentKind.known.enumerated().map { index, kind in
            AgentActivity(
                kind: kind,
                startedAt: Date().addingTimeInterval(-Double(index) * 30 - 20),
                status: "Working on something"
            )
        })
        if !render(environment, named: "agent-marks", into: directory) { failures += 1 }

        // One deliberately opinionated setup exercises every appearance value
        // together: wide tinted panel, custom colour, softer chrome, and the
        // largest supported curves. Defaults alone cannot catch clipping at the
        // ends of the customization ranges.
        environment.settings.preferences.accent = .custom
        environment.settings.preferences.customAccentHex = "FF4F9A"
        environment.settings.preferences.panelStyle = .tinted
        environment.settings.preferences.panelWidth = 680
        environment.settings.preferences.panelOpacity = 0.9
        environment.settings.preferences.bottomCornerRadius = 38
        environment.settings.preferences.flareRadius = 20
        environment.settings.preferences.rimStrength = 0.5
        environment.settings.preferences.shadowStrength = 0.35
        environment.notch.tab = .home
        if !render(environment, named: "expanded-customized", into: directory) { failures += 1 }

        return failures == 0 ? 0 : 1
    }

    // MARK: Rendering

    /// A wide, high-contrast stand-in that exercises browser artwork cropping
    /// and makes overflow obvious in generated UI previews.
    private static func sampleVideoArtwork() -> NSImage {
        NSImage(size: NSSize(width: 320, height: 180), flipped: false) { rect in
            NSColor(calibratedRed: 0.82, green: 0.10, blue: 0.18, alpha: 1).setFill()
            rect.fill()

            NSColor(calibratedWhite: 0.06, alpha: 0.9).setFill()
            NSRect(x: 0, y: 0, width: rect.width * 0.4, height: rect.height).fill()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 34, weight: .heavy),
                .foregroundColor: NSColor.white
            ]
            NSString(string: "LIVE").draw(
                at: NSPoint(x: rect.width * 0.08, y: rect.height * 0.36),
                withAttributes: attributes
            )
            return true
        }
    }

    private static func render(
        _ environment: AppEnvironment,
        named name: String,
        into directory: URL
    ) -> Bool {
        let size = environment.notch.geometry.windowSize
        let view = NotchRootView(environment: environment, isRenderingOffscreen: true)
            .frame(width: size.width, height: size.height)
            // The panel is transparent by design; a backdrop makes the
            // silhouette readable in a flat image.
            .background(Color(white: 0.18))
            .environment(\.isRenderingOffscreen, true)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("error: could not render \(name)\n".utf8))
            return false
        }

        let url = directory.appendingPathComponent("\(name).png")
        do {
            try png.write(to: url)
            print("rendered \(url.path)")
            return true
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            return false
        }
    }

    /// Deterministic content so previews are comparable between runs.
    private static func seedSampleData(_ environment: AppEnvironment) {
        // Unlock Pro in the throwaway domain so the gated widgets render as
        // themselves rather than as the upsell.
        if let key = LicenseValidator.makeKey(payload: "BEEF1234") {
            environment.settings.preferences.licenseKey = key
        }

        // Something recognisable on the shelf. Falls back to nothing if the
        // machine has no files in these locations.
        let candidates = [
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ].compactMap { $0 }

        let samples = candidates
            .flatMap { directory in
                (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
            }
            .prefix(4)
        environment.shelf.add(urls: Array(samples))

        environment.events.post(NotchEvent(
            kind: .download, title: "Xcode_26.xip", subtitle: "Download complete · 7.4 GB"
        ))
        environment.events.post(NotchEvent(
            kind: .music, title: "Weightless", subtitle: "Marconi Union"
        ))
        environment.events.post(NotchEvent(
            kind: .system, title: "Low Battery", subtitle: "14% remaining"
        ))
        // Carries an agent, so the row draws that agent's mark rather than the
        // generic symbol for its kind.
        environment.events.post(NotchEvent(
            kind: .agent,
            title: "Claude finished",
            subtitle: "Worked for 4:00",
            agent: .claude
        ))
        environment.events.post(NotchEvent(
            kind: .agent,
            title: "Codex finished",
            subtitle: "Worked for 1:12",
            agent: .codex
        ))
    }
}
