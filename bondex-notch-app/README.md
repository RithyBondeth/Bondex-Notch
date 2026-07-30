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
  `NowPlayingService` scripts Music.app and Spotify instead, which is supported
  and App Store safe. It costs an Automation consent prompt on first use, and
  covers only those two players.
- **Reading other apps' notifications.** There is no API for this and the
  Notification Center store is SIP-protected. The "Activity" widget is a feed of
  what Bondex observes directly — track changes, completed downloads, power
  events, shelf drops — and is named accordingly.

## Permissions

All three are optional and requested only when the relevant widget is enabled.

| Permission | Needed for | Prompted by |
|---|---|---|
| Automation | Music / Spotify widget | first AppleScript call |
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
