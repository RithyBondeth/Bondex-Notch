# Bondex Notch

A native macOS utility that turns the display notch into a live view of what
your Mac is doing — music, downloads, system status, and a drag-and-drop shelf.

Swift 6 · SwiftUI · AppKit · no third-party dependencies.

## Build and run

```bash
./scripts/build-app.sh release
```

That produces `build/Bondex Notch.app`. Open it:

```bash
open "build/Bondex Notch.app"
```

The app is an agent (`LSUIElement`), so there is no Dock icon. It lives in the
notch and in the menu bar; use the menu bar item for Settings and Quit.

Run the tests:

```bash
swift test
```

For a universal (arm64 + x86_64) binary:

```bash
./scripts/build-app.sh release --universal
```

`swift build` alone produces a working executable, but run it from the bundle —
several system frameworks (notably `UNUserNotificationCenter`) need a real
bundle identifier.

## Architecture

```
Sources/BondexNotch/
  App/         Entry point, delegate, composition root, menu bar
  Window/      NSPanel, geometry, pointer tracking, panel state machine
  Model/       Preferences, licensing, events, state enums
  Services/    Now playing, system metrics, file activity, shelf, notifications
  Views/       Notch silhouette, collapsed/peek/expanded, widgets, settings
  Support/     Theme, motion, logging, offscreen preview renderer
```

The layering is one-directional: `Views` observe `Services` and `Model` through
`AppEnvironment`, and nothing in `Services` knows about `Views`.

### The panel

`NotchPanel` is a non-activating `NSPanel` one level above the status window, so
it can overlap the menu bar without ever stealing focus. It is created once at
the *largest* footprint it will ever need and never resized — the SwiftUI spring
animates the content inside it. Because that leaves most of the window
transparent, `PassthroughHostingView` overrides `hitTest` to reject points
outside the currently visible shape, so clicks fall through to the app
underneath.

Hover is driven by a global `NSEvent` monitor rather than SwiftUI's `.onHover`,
which is unreliable in a panel that is rarely key. Global *mouse* monitors need
no accessibility permission.

`NotchGeometry` measures the hardware notch from `NSScreen.safeAreaInsets` and
`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Displays without a notch get a
synthetic 190×32 pill so the interaction is identical everywhere. Everything is
re-derived on `didChangeScreenParametersNotification`.

### States

| State | Size | When |
|---|---|---|
| `collapsed` | exactly the notch | nothing live; invisible on notched Macs |
| `peek` | notch + strips either side | media playing, or a transient banner |
| `expanded` | 560 × 210 | pointer on the notch, or clicked to pin |

## What macOS does and does not allow

Two features in the original proposal cannot be built as literally described.
Both are handled with the supported alternative rather than a private API:

- **System-wide Now Playing.** `MPNowPlayingInfoCenter` reports only the calling
  process, and the private MediaRemote framework was gated in macOS 15.4.
  `NowPlayingService` reads the apps themselves instead, which is supported and
  App Store safe. It costs an Automation consent prompt per app on first use.
  - Music and Spotify expose a scripting dictionary that names the current
    track directly.
  - Browsers do not, so `BrowserMediaReader` asks the *tab* instead: it locates
    the tab holding audio and evaluates a small script in it, reading the
    `<video>`/`<audio>` element for transport state and
    `navigator.mediaSession.metadata` for title, artist and artwork. That is
    what makes YouTube, YouTube Music, SoundCloud, Twitch and the rest visible.
    Safari and every Chromium browser ship with **"Allow JavaScript from Apple
    Events" turned off**; until it is on, reads fail with `errAEEventNotPermitted`
    and the panel says so rather than showing an empty widget. Firefox has no
    scripting dictionary at all and cannot be supported.
  - Some Chromium forks — ChatGPT Atlas is the one seen so far — inherit Chrome's
    `execute javascript` command while exposing no menu item or preference that
    would ever permit it. Those are read from the window title instead: the
    browser appends a speaker glyph to a window whose tab is audible. That yields
    a title and nothing else, so `NowPlaying.supportsTransport` is false and the
    UI drops the transport controls rather than showing buttons that do nothing.
    The marker says only that *some* tab in the window is making noise while the
    window is named for its *active* tab, so the audible tab is identified (the
    active tab if it is on a media host, else the window's sole media-host tab)
    rather than assumed — otherwise a video in one tab is reported as whatever
    the user happens to be looking at in another.
- **Reading other apps' notifications.** There is no API for this and the
  Notification Center store is SIP-protected. The "Activity" widget is a feed of
  what Bondex observes directly — track changes, completed downloads, power
  events, shelf drops — and is named accordingly.

## Permissions

All three are optional and requested only when the relevant widget is enabled.

| Permission | Needed for | Prompted by |
|---|---|---|
| Automation | Music widget, per app read | first AppleScript call |
| Files and Folders | Downloads watching | first read of `~/Downloads` |
| Notifications | Bondex posting its own alerts | Settings → Permissions |

Ad-hoc signatures change on every rebuild, so macOS treats each build as a new
app and re-prompts. Sign with a stable Developer ID identity to keep grants.

## Licensing

`LicenseValidator` is a **format and checksum check, not DRM** — it exists so the
Free/Pro split is wired end to end. Before shipping paid builds, replace it with
StoreKit 2 entitlements or a server-signed receipt.

Generate a test key:

```swift
LicenseValidator.makeKey(payload: "BEEF1234")   // BNDX-BEEF-1234-…
```

## Keeping it cheap

This is an agent that runs all day, so two costs are load-bearing and easy to
reintroduce. Both were measured on the running app, not guessed.

- **Continuous animation must belong to Core Animation, not to SwiftUI.** The
  peek is on screen for as long as anything is playing. Driving its equaliser
  from a `TimelineView`, or from a `repeatForever` `scaleEffect`, keeps the
  animation on the display cycle and costs **5–10% CPU continuously** — a tick
  re-enters the transaction machinery and re-renders the panel. `AudioBarView`
  installs a `CABasicAnimation` per bar instead and the render server takes it
  from there, for ~0 app CPU. Measured end to end: **12–14% → 3%**.
- **Apple Events are charged per property, not per script.** Asking each tab for
  its URL and title one at a time is a separate round trip every time; on a
  browser with a handful of windows open that measured **1.1s per call**, once a
  second. `URL of every tab of window n` returns the list in a single event —
  the same read costs ~185ms, and the window-title path descends into a window
  only when it carries the audible marker.

## Previewing the UI offscreen

The panel overlays the menu bar, which makes it awkward to screenshot. This
renders every state to PNG without a display:

```bash
"build/Bondex Notch.app/Contents/MacOS/BondexNotch" --render-previews ./previews
```

It runs against a throwaway `UserDefaults` domain (it unlocks Pro to exercise
the gated widgets) and never touches real preferences. Two caveats, both
`ImageRenderer` limitations rather than app behaviour: `.onDrop` cannot be
rasterised, and `ScrollView` renders empty — `NotchRootView` and
`ScrollingStack` both degrade when `\.isRenderingOffscreen` is set.

## Known gaps

- Downloads without a sidecar file report bytes received and live rate, not a
  percentage — no public API exposes a transfer's expected total size.
- The shelf holds file *references*. Moving or deleting a file elsewhere leaves
  a stale tile until it is removed.
- Preferences are `UserDefaults`-backed. The proposal called for Core Data /
  SQLite; nothing yet stores enough history to need it.
- Tests cover the file watcher, licensing, the event feed, geometry and
  formatting. The AppleScript bridge and the mach/IOKit samplers are exercised
  only by running the app — neither is practical to fake without first putting
  a protocol in front of it.
