# Bondex Notch

A native macOS utility that turns the display notch into a live view of what
your Mac is doing — music, downloads, system status, and a drag-and-drop shelf.

Swift 6 · SwiftUI · AppKit · no third-party dependencies.

## Build and run

```bash
./scripts/build-app.sh release --universal
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

For a faster build targeting only the current Mac during development:

```bash
./scripts/build-app.sh debug
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
| `peek` | notch + 120 while playing, + 90 per extra agent, + 260 for a banner | media playing, an agent working, or a transient banner |
| `expanded` | user-controlled 440–680 wide, height **measured from the content** | pointer on the notch, or clicked to pin |

Only the widths are fixed. The expanded panel's height comes from what it is
actually showing: `ExpandedView` reports its laid-out height through
`ExpandedHeightKey`, and `NotchViewModel.contentSize` clamps that between a floor
and `expandedContentSize.height` — a *ceiling*, not the panel's size.

This is worth keeping. A single fixed height cannot be right for every tab, and
getting it wrong is not obvious: the panel mask simply cuts the bottom off
whatever overflowed, which reads as inconsistent padding rather than as clipping.
Both directions were shipped and reported before this was measured instead —
Home clipped its gauges once a media row appeared, and Music sat in dead space
whenever the height was raised enough to fix Home. Tabs that scroll opt out with
`NotchTab.widgetHeight`, because a panel that resized as feed items arrived and
aged out would be worse than one that stays put.

### Agent activity

While a coding agent is working, the peek shows its mark on one side of the notch
and its name on the other. What it is doing, and how long it has been at it, are
one hover away: expanding the panel puts an agent card at the top of Home with a
row per agent — status and a running clock.

That split is deliberate. All three used to be crammed into the strip beside the
notch, where the status — the only part carrying new information — was the first
thing to be truncated. What belongs over the menu bar all day is the smallest
true statement, *who is working*; what they are working on is a question, and a
question deserves a deliberate look rather than a permanent slab of text. It also
takes the peek's last `TimelineView` with it, so the strip no longer re-renders
once a second for the entire length of a run.

Several agents at once is an ordinary case, not a corner one — a Claude Code
session and a Codex session on the same machine signal independently. Each gets
its own mark and its own name, tinted to match so the pairing needs no
explaining, and the peek widens as agents join. The card lists three and then
counts, because the panel is measured from its content and an unbounded list
would push Home past its height ceiling and be silently cut off at the bottom.

Agent presence works without configuration. Bondex scans executable names, not
usernames, versioned installation folders, CPU usage, or a fixed application
path, so standard CLI, editor-extension, and desktop-host installs are detected
wherever they live. A presence-only agent is labelled `Open`; Bondex does not
pretend that an open process is actively thinking.

Hooks are optional enrichment. They replace `Open` with the exact live state —
for example `Thinking`, `Editing`, or `Running tests`. This distinction matters
because agents spend most turns waiting on network responses or child tools, so
CPU usage cannot reliably reveal whether a turn is active.

An agent can declare detailed activity through one hook:

```bash
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" --agent-busy claude "Editing Foo.swift"
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" --agent-idle claude
```

Codex can use its structured hook payload directly, with the same command on
`PreToolUse`, `Stop`, and `SessionEnd`:

```bash
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" --agent-hook codex
```

Bondex reads the JSON from stdin itself, so this needs no `jq`. Shell commands
become statuses such as `Running swift test`, patches name the file being edited,
and MCP or local tools get a readable tool name. Existing Codex hooks that pass
the literal status `Working` are enriched the same way, preserving their hook
trust approval.

Settings › Widgets shows the appropriate command with this installation's real
binary path filled in, and a Copy button. Nothing depends on the developer's
project directory or username. Explicit integrations wire `--agent-busy` per
tool call and `--agent-idle` at the end of a turn; Codex uses `--agent-hook` for
both.

Any agent name works, not just the ones Bondex ships artwork for — an unknown
agent shows up under the generic mark with the name it gave. A closed list would
mean every new agent needed a release before it could light the notch at all.
What *is* rejected is a name that could not safely be a file name, because that
is exactly what it becomes: `--agent-busy ../../../etc/passwd` must not write
outside the signal directory. A malformed name exits non-zero with a message
rather than being ignored — a hook fires dozens of times a turn, which is where a
silent misreading does the most damage.

Where those two lines go differs per agent, and Settings names the file for the
three that were checked against their installed builds. All three borrow Claude
Code's `{matcher, hooks:[{type, command}]}` shape; Gemini renames the events:

| Agent | File | Busy / idle events |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | `PreToolUse` / `Stop` |
| Codex | `~/.codex/hooks.json` | `PreToolUse` / `Stop` |
| Gemini CLI | `~/.gemini/settings.json` | `BeforeTool` / `AfterAgent` |

Claude Code's CLI and desktop app read the same file, so wiring it once covers
both.

Those write and remove `~/.bondex-notch/agents/<agent>`, which the app watches
with a dispatch source. Process presence is sampled every five seconds to cover
desktop hosts that do not forward user hooks. The file's modification date is a
heartbeat and its first line is the status to show. A 90-second staleness
backstop covers an agent killed mid-run without its idle hook firing; it is
deliberately long, because it must sit through a single slow tool call without
blinking out.

The orb is Core Animation, not SwiftUI, for the reason in *Keeping it cheap* —
it is on screen for the entire length of a run.

The marks inside it are geometry, not image assets, which is why this project
still ships no image files. A mark drawn as a path scales without a set of
`@2x`/`@3x` exports and is tinted by *fill* rather than by compositing — which
matters on a near-black panel, where anything with a baked-in background shows as
a pale rectangle around the glyph. Claude's is a grid of strings because it *is*
a grid; the rest are curves, and the ones that are drawn as lines are stroked
into outlines at build time so every renderer has one thing to draw and one place
to set a colour.

They are simplified rather than traced. The glyph is about 13pt across, so detail
below roughly half a point is not resolvable and costs path complexity for
nothing; what has to survive is the silhouette, because that is what makes a mark
recognisable at a glance. Claude's grid is the one place this bites in the other
direction — at that size a cell is under a point and the eyes are a single cell,
so cells are drawn at exactly one cell with no overlap: dilating each one to hide
seams instead closes the gaps that are the eyes.

Geometry has no compile-time proof that it looks like anything, so
`--render-previews` writes an `agent-marks` sheet of every mark. That is the only
way to check the artwork — and no ordinary session has five agents running.

Process discovery is still here, but only to answer "is this agent installed",
which is what lets Settings show setup instructions for the agents you use and
stay quiet about the rest. `proc_pidpath` resolves every process the user owns
(measured at 617 of 617). Matching is case-sensitive on purpose: Claude Code's
binary is `claude`, the Claude desktop app's is `Claude`.

### Customization

Appearance settings apply live and persist as part of the version-tolerant
preferences blob. Users can choose a preset or custom accent, pure-black,
gradient, or accent-tinted panel treatment, panel width, opacity, bottom-corner
and top-flare geometry, rim and shadow strength, and animation speed. Widget
settings also control which tabs exist and their left-to-right order. CPU,
memory, battery, and network throughput live together in a dedicated System tab;
an optional compact summary can also be shown on Home. The AppKit window always
reserves the maximum footprint, so changing the width or shape does not resize
the window or interrupt the panel animation.

The full System widget includes a compact device-battery panel for the Mac and
connected accessories that publish battery levels through IORegistry, including
supported keyboards, mice, trackpads, and headphones. Charging devices use a
green bolt treatment, low devices use a warm warning colour, and every value has a VoiceOver
label. Discovery is read-only, requires no Bluetooth pairing or privacy
permission, and gracefully omits hardware whose driver does not expose a level.

Volume, mute, display brightness, and keyboard-backlight keys produce a compact
meter beside the notch with the current percentage. Power-source and charging
transitions use the same surface for battery feedback without adding routine
discharge steps to the activity feed. Hardware feedback temporarily outranks
playback and notification peeks, dismisses after a short delay, and can be
disabled independently in Widget settings.

### Microphone and camera privacy indicator

While an input device is in use, a compact persistent peek shows an orange
microphone mark, a green camera mark, or both. The same marks stay visible in the
expanded header, so opening another widget does not hide the active-device state.
The indicator can be disabled independently in Widget settings and announces
state changes through VoiceOver when important announcements are enabled.

Detection reads the public CoreAudio and CoreMediaIO device running-state APIs.
Bondex never opens or records either stream and does not request microphone or
camera permission. macOS does not expose the responsible application's identity
through these public APIs, so the indicator intentionally reports the device,
not an app name.

### Accessibility and keyboard control

Bondex follows the macOS Reduce Motion, Increase Contrast, and Reduce
Transparency settings. Reduce Motion replaces directional panel transitions and
continuous agent/media animation with short fades or still artwork; contrast and
transparency preferences strengthen the panel automatically. Important app
events can be announced through VoiceOver, while system volume and brightness
are left to macOS so they are not spoken twice.

Permission-free global shortcuts open the notch (`⌃⌥ Space` by default) or jump
straight into Quick Capture (`⌃⌥ C` by default), with alternatives in Settings.
Once open, Left and Right Arrow cycle tabs and Escape closes the panel. Keyboard-
focused tab chips and controls get a visible outline. The hardware-HUD display
time is also configurable.

### Custom shortcuts

The Shortcuts tab holds up to eight user-defined quick actions. An action can
open a selected macOS application, run an Apple Shortcut by name, or enable and
disable a Bondex widget. Actions can be renamed and reordered in Settings, and
application tiles keep both the bundle identifier and selected path so they
survive ordinary app moves while retaining a fallback.

Apple Shortcuts are launched with `/usr/bin/shortcuts` and a structured argument
array; user-provided names are never evaluated as shell text. Application actions
use Launch Services, widget actions mutate only their corresponding preference,
and every tile exposes its purpose to VoiceOver.

### Focus timer and meetings

Home includes a restart-safe focus timer with start, pause, resume, and cancel
controls. An active timer lives compactly beside the notch and is also available
from the menu-bar menu. Scripts and Shortcuts can control the running app:

```bash
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" --focus-start 25
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" --focus-pause
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" --focus-resume
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" --focus-cancel
```

Upcoming meetings are opt-in and use EventKit's full calendar authorization.
The next event appears on Home within two hours and in the compact notch within
ten minutes, with a Join action for supported web meeting links. Compact meeting
titles are hidden by default so screen sharing does not expose calendar details.

### Clipboard history

The Clipboard tab keeps a searchable, deduplicated history of text, links, and
images copied during the current app session. Items can be copied again, pinned,
removed individually, or cleared together, and capture can be paused instantly.
The history is bounded and memory-only: clipboard contents are never written to
disk. Entries marked concealed, transient, or auto-generated by their source
(including compatible password managers) are ignored.

### Quick Capture

Quick Capture is a restart-persistent local inbox for short notes and links.
Press `⌃⌥ C` by default to open the notch directly into the capture field, type,
and press Return to save. A paste button pulls copied selected text into the
draft without saving it automatically. Captures can be searched, copied again,
pinned, opened when they are links, removed individually, or cleared together.
The shortcut is permission-free and configurable in Settings; captures remain
in Bondex Notch's local preferences and are never transmitted.

### Custom live activities

Any script, Shortcut, build tool, or terminal session can publish progress into
Bondex without an SDK:

```bash
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" \
  --live-start build --title "Building release" --progress 0.2
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" \
  --live-update build --subtitle "Running tests" --progress 0.75
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" \
  --live-finish build --message "Build succeeded"
```

Progress is a number from `0` to `1`. IDs use letters, digits, `-`, and `_` and
identify the activity across updates. Active items appear in the persistent
peek, at the top of Home, and in the reorderable Live tab. Finishing one turns
it into a normal activity-feed event and removes its signal. Signals are small
JSON files in `~/.bondex-notch/live`; the app watches the directory with a
dispatch source, so there is no polling when nothing changes. An abandoned
activity expires after 24 hours.

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
  - Dia exposes its tabs through AppleScript, but enables page JavaScript only
    when launched with `--enable-applescript-javascript`. Bondex detects the
    disabled state and shows the exact relaunch command in the Music tab.
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

- **Gemini's hooks are not yet verified.** They are written from its own settings
  schema, but `gemini -p` hangs with no output in a non-TTY. Claude Code and Codex
  hooks are verified firing. Everything on the Bondex side remains
  agent-agnostic, so this is a question of where each agent reads its hooks from,
  not of the indicator.
- The opencode mark is a placeholder — a block cursor standing in until the real
  artwork is to hand.
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
