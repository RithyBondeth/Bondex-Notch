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

To package a distributable disk image (`.dmg`) with a drag-and-drop Applications shortcut:

```bash
./scripts/build-dmg.sh
```

It always builds a fresh universal release first and refuses to package a
bundle that is not universal. `--skip-build` packages the existing bundle.

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
  Model/       Preferences, events, state enums
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

Pointer tests use `NSMouseInRect` (via `NotchGeometry.pointer(_:isIn:)`), not
`CGRect.contains`. A cursor pushed against the top of the display reports a y
equal to the screen's `maxY`, and `contains` treats that edge as outside, so the
notch ignored exactly the gesture people use to reach it: throwing the pointer
at the top of the screen.

Hovering opens the panel transiently; it closes when the pointer leaves. A click
on the notch or anywhere in the open panel latches it, and it then closes on a
click elsewhere, Escape, the close button or the shortcut. While the panel has
keyboard focus (Quick Capture, a search field, the palette) the pointer leaving
does not close it, and closing hands keyboard focus back to the app you came
from.

`NotchGeometry` measures the hardware notch from `NSScreen.safeAreaInsets` and
`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Displays without a notch get a
synthetic 190×32 pill so the interaction is identical everywhere. Everything is
re-derived on `didChangeScreenParametersNotification`.

With more than one display, Settings › General › "Show the notch on" decides
where the panel lives (`NotchPlacement`). By default it follows the pointer: once
the pointer has stayed on another display for about half a second, the notch
fades across to it — immediately if the pointer is pushed into that display's
top centre, and never while the panel is open or a drag is over it. "The
built-in display" keeps it on the laptop (falling back to the main display with
the lid closed), and "The built-in display only" hides it with the lid closed.
The old "Show synthetic notch on external displays" switch migrates: off becomes
built-in only.

### States

| State | Size | When |
|---|---|---|
| `collapsed` | exactly the notch | nothing live; invisible on notched Macs |
| `peek` | notch + 120 while playing, + 50 per extra agent, + 300 for a banner | media playing, an agent working, or a transient banner |
| `expanded` | user-controlled 440–680 wide, height **measured from the content** | pointer on the notch, or clicked to pin |

A peek is two wings either side of the camera housing, each exactly half of the
width that is not notch. Widths are chosen so each wing holds what it shows —
the volume rail, a banner line — because anything drawn in the middle is under
the hardware and invisible.

Only the widths are fixed. The expanded panel's height comes from what it is
actually showing: `ExpandedView` reports its laid-out height through
`ExpandedHeightKey`, and `NotchViewModel.contentSize` clamps that between a floor
and `expandedContentSize.height` — a *ceiling*, not the panel's size.

This is worth keeping. A single fixed height cannot be right for every tab, and
getting it wrong is not obvious: the panel mask simply cuts the bottom off
whatever overflowed, which reads as inconsistent padding rather than as clipping.
Both directions were shipped and reported before this was measured instead —
Home clipped its gauges once a media row appeared, and Music sat in dead space
whenever the height was raised enough to fix Home. List tabs are measured too,
up to a cap (`NotchTab.widgetHeight`) past which they scroll. They used to be
held at exactly that height, which left two clipboard items floating in a
list-sized gap; items arrive while the panel is closed, so a list rarely changes
size while you are looking at it. The cap is applied by `HeightCap`, because a
`.frame(maxHeight:)` grows to its maximum whenever it is offered more.

Switching tabs slides the new widget in from the side of the strip it was picked
from, and the selection pill slides between chips. Every label uses the five-step
`Theme.TextSize` scale, list rows share `notchRow()`, and radii come from
`Theme.Radius`, so widgets read as one surface rather than eleven.

### Agent activity

While a coding agent is working, the peek shows its mark on one side of the notch
and how long it has been working on the other. What it is doing is one hover
away: expanding the panel puts an agent card at the top of Home with a row per
agent — status, project, model and the same clock.

That split is deliberate. Status used to be crammed into the strip beside the
notch, where it — the only part that changes every few seconds — was the first
thing to be truncated. The mark already says *who* is working, so a name beside
it only repeated the other half of the strip; the run's length is what tells you
whether to go and look. One agent gets a clock at normal size. Several get small
clocks, two to a column with the columns side by side, because the strip is only
as tall as the menu bar. Each clock is tinted like its mark.

The clocks are SwiftUI's self-advancing timer text, so only the digits redraw
each second — the strip's view is not re-evaluated, and there is no
`TimelineView`.

Only agents a hook reports working reach the peek. One that is only known to be
open is listed in the expanded panel, labelled `Open` with a still mark, and
nowhere else: the Claude and ChatGPT desktop apps each carry an agent binary, so
"open" is true all day, and a strip saying so over the menu bar told you nothing.

Several agents at once is an ordinary case, not a corner one — a Claude Code
session and a Codex session on the same machine signal independently. Each gets
its own mark and its own name, tinted to match so the pairing needs no
explaining, and the peek widens as agents join. The card lists three and then
counts, because the panel is measured from its content and an unbounded list
would push Home past its height ceiling and be silently cut off at the bottom.

Agent presence works without configuration. Bondex scans executable names, not
usernames, versioned installation folders, CPU usage, or a fixed application
path, so standard CLI, editor-extension, and desktop-host installs are detected
wherever they live. A presence-only agent is labelled `Open` in the panel and
kept out of the peek; Bondex does not pretend that an open process is actively
thinking.

Hooks are optional enrichment. They replace `Open` with the exact live state —
for example `Thinking`, `Editing`, or `Running tests`. This distinction matters
because agents spend most turns waiting on network responses or child tools, so
CPU usage cannot reliably reveal whether a turn is active.

An agent can declare detailed activity through one hook:

```bash
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" --agent-busy claude "Editing Foo.swift"
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" --agent-idle claude
```

Claude Code and Codex can use their structured hook payloads directly, with the
same command on every event:

```bash
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" --agent-hook claude
"/path/to/Bondex Notch.app/Contents/MacOS/BondexNotch" --agent-hook codex
```

Bondex reads the JSON from stdin itself, so this needs no `jq`. Shell commands
become statuses such as `Running swift test`, patches name the file being edited,
and MCP or local tools get a readable tool name. Existing Codex hooks that pass
the literal status `Working` are enriched the same way, preserving their hook
trust approval.

### Needs you

When an agent stops to wait for you, the notch says so. A permission prompt
(Claude Code's `Notification` event, or `PermissionRequest` in Claude Code and
Codex), a question (`AskUserQuestion`), a plan awaiting approval
(`ExitPlanMode`) or Codex's `request_user_input` marks the agent as waiting. Other agents can do the same with
`--agent-attention <agent> "what it needs"`. A waiting agent outranks every
persistent peek apart from the camera and microphone indicator: its ring turns
amber and pulses, and "Needs you" replaces its clock. In the panel, its row shows
what it is waiting for. The next event from the agent clears it.

Waiting is exempt from the 90-second staleness backstop — no heartbeat arrives
while an agent is blocked on you, so it would otherwise vanish after a minute and
a half of being ignored. It expires after 30 minutes instead.

A macOS notification follows only if the wait is still unanswered after 20
seconds, so working at the terminal does not ping you on every prompt. Runs of two
minutes or more also notify when they finish. Both can be turned off in
Settings › Widgets, and permission to notify is asked for the first time one is
due. Claude Code's idle reminder ("waiting for your input" after a turn ends) is
not a wait and is ignored.

The setup includes `PostToolUse`, so an approved tool stops showing "Needs you"
as soon as it finishes rather than at the agent's next event.

### Hook setup

For Claude Code and Codex, Settings › Widgets sets the hooks up itself. **Set
Up** adds one `--agent-hook` command per event, with this copy of the app's
real path, to the agent's own file. Each time Settings opens it checks them
again and offers **Update** when events are missing — typically a setup from
before "Needs you" — or **Use This Copy** when they run a copy of the app that
has moved or no longer exists. Both failures are otherwise silent: the notch
just never lights up. **Remove Bondex Hooks** takes out Bondex's hooks and
nothing else.

The file is edited, not rewritten. Keys keep their order, numbers their
spelling and the file its indent, so a file laid out the way the agents write
theirs changes only by the lines added; the original is kept beside it as
`<name>.bondex-backup`. Existing hooks keep their position, which matters to
Codex: it keys hook trust on position, and holds back new or changed hooks until
they are reviewed. A linked file is edited through the link, and its permissions
are kept. A file that is not plain JSON (one with comments, say) is left
untouched, and Settings shows the command to add by hand instead.

Other agents get the commands to paste, with the binary path filled in. Explicit
integrations wire `--agent-busy` per tool call and `--agent-idle` at the end of
a turn.

Any agent name works, not just the ones Bondex ships artwork for — an unknown
agent shows up under the generic mark with the name it gave. A closed list would
mean every new agent needed a release before it could light the notch at all.
What *is* rejected is a name that could not safely be a file name, because that
is exactly what it becomes: `--agent-busy ../../../etc/passwd` must not write
outside the signal directory. A malformed name exits non-zero with a message
rather than being ignored — a hook fires dozens of times a turn, which is where a
silent misreading does the most damage.

The events were read off each agent's installed build. All three borrow Claude
Code's `{matcher, hooks:[{type, command}]}` shape; Gemini renames the events:

| Agent | File | Events |
|---|---|---|
| Claude Code | `~/.claude/settings.json` (or `CLAUDE_CONFIG_DIR`) | `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SessionEnd` |
| Codex | `~/.codex/hooks.json` (or `CODEX_HOME`) | `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`, `SessionEnd` |
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

### Agent usage

The Agents tab is a small dashboard for Claude Code and Codex: plan limits with
renewal countdowns, what the tokens would have cost at public API prices, which
agent was active last, and an hourly or daily trend. Everything comes from
files the agents already write on this Mac. Bondex signs in to nothing, reads no
credentials and sends nothing.

| Figure | Source |
|---|---|
| Claude tokens, spend, sessions, projects and models | `~/.claude/projects/**/*.jsonl` (and `CLAUDE_CONFIG_DIR`) |
| Claude plan limits | `~/Library/Application Support/Claude/plan-usage-history.json`, kept by the Claude desktop app while it runs |
| Claude plan name | `oauthAccount.organizationType` and its rate-limit tier in `~/.claude.json`; nothing else in that file is kept |
| Codex tokens, spend, limits, plan, sessions, projects and models | `~/.codex/sessions/**/*.jsonl` (and `CODEX_HOME`) |

A session is named for the folder it was started in, so a session that `cd`s
into a subfolder stays one project, and a worktree is named for its repository.
The Sessions card lays live hook status over each working agent's newest
session, with the same spinning mark as the peek. The orb spins only for work a
hook reported: an agent that is merely open shows a still mark.

Claude Code writes one log line per content block, each repeating the request's
usage, and copies earlier turns into a resumed session's file. Requests are
therefore counted once by message and request ID. When a request lists
`usage.iterations` — a compaction pass, or a refused attempt before a fallback
model answered — every iteration is billed at its own model's rates, as the API
bills it; the top-level counts cover only the final attempt. US-only inference
(×1.1) and web searches ($0.01 each) are added. Codex reports cached input as
part of input and repeats its running total whenever only the rate limits move;
both are accounted for. The Claude app records percentages but not renewal
times, so the session countdown is taken from the hour its run of readings
began, and the weekly one from the last drop in the history. Where neither can
be worked out, no countdown is shown rather than a guess.

Prices live in `AgentPricing` as a static table. Model IDs are matched exactly,
after stripping date stamps and provider prefixes, so an unknown model is counted
but not priced and the total is shown as a minimum (`≥`). Long-context
surcharges are not modelled.

To check a figure from a terminal, `--agent-usage-report` runs the same scan
and prints every total the tab would show:

```bash
"build/Bondex Notch.app/Contents/MacOS/BondexNotch" --agent-usage-report
```

Logs are read incrementally on a utility queue. The first scan covers the last
31 days; each later one reads only bytes appended since, and only complete
lines. A raw-byte filter skips lines that cannot carry usage before any JSON is
decoded. On 423 MB of synthetic logs the first scan took 2.7 s and a rescan
3 ms. Usage is kept as 15-minute slots, so day boundaries are exact in every time
zone.

What the scan has counted is saved to `~/Library/Caches/<bundle id>/agent-usage.plist`
at most every five minutes and when the app quits, along with how far into each
log it got. The next launch carries on from there instead of reading the month
again: on a real 30-day history the first scan went from 6.1 s to 0.06 s, with
identical totals, for a 719 KB file. A cache written by a different build or for
different log folders is ignored and rebuilt, and turning the Agents tab off
deletes it.

### Customization

Appearance settings apply live and persist as part of the version-tolerant
preferences blob. Users can choose a preset or custom accent, pure-black,
gradient, or accent-tinted panel treatment, panel width, opacity, bottom-corner
and top-flare geometry, rim and shadow strength, and animation speed. Widget
settings also control which tabs exist and their left-to-right order. New
installs start with Home, Agents, Capture, Music, Clipboard and Shelf; System,
Live, Files, Activity and Shortcuts are one toggle away. CPU,
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
meter beside the notch with the current percentage. Apple silicon Macs have no
`IODisplayConnect` service and no public brightness API, so the built-in
display's level is read with `DisplayServicesGetBrightness`, looked up at run
time and only ever read; the classic IOKit parameter remains the fallback.
Brightness is announced only for the brightness keys, never from polling, so
automatic brightness drifting with ambient light does not pop the HUD. Power-source and charging
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

Detection reads the public CoreAudio and CoreMediaIO running-state APIs. The
microphone is checked per process (`kAudioProcessPropertyIsRunningInput`),
because the device-level flag cannot tell input from output: AirPods and USB
headsets are one device with both directions, and playing music through them
used to light the microphone mark.
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

Permission-free global shortcuts open the notch (`⌃⌥ Space` by default), jump
straight into Quick Capture (`⌃⌥ C`) or open the Command Palette (`⌃⌥ P`). Each
can be switched off or recorded afresh in Settings › General: click the
shortcut, then press the new one, or Escape to keep the old. A shortcut needs
⌘, ⌃ or ⌥ unless it is a function key, the ones every app relies on (⌘Q, ⌘W,
⌘C, ⌘V and the like) are refused, and one another app has already claimed is
flagged so it can be changed. Choices from the earlier preset lists carry over.
Once open, Left and Right Arrow cycle tabs (while a text field is being edited
they move the caret instead) and Escape closes the panel. Keyboard-
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
controls. Idle, it is a small chip at the foot of Home; a running session gets a
card at the top. An active timer lives compactly beside the notch and is also available
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

macOS now alerts the user when an app reads the clipboard without them pasting,
and a clipboard history is exactly that kind of read. On macOS 15.4 and later
Bondex therefore reads nothing until access is granted: the tab explains why
and asks once, and the history starts after Bondex Notch is set to Allow under
Privacy & Security › Paste from Other Apps (macOS may apply the change only
after Bondex is relaunched). While macOS is set to ask or deny, the tab says so
and links to that setting rather than prompting on every copy.

### Shelf

Files dragged onto the notch are parked on the Shelf until they are dragged out
or removed, and the Shelf is kept across restarts. Files stay where they are and
are remembered by bookmark, so one that is moved or renamed is found at its new
path; one that is deleted or moved to the Trash shows as missing and is dropped
at the next launch. Image data with no file of its own — the floating
screenshot thumbnail, an image dragged from a browser — is copied into
`~/Library/Application Support/<bundle id>/Shelf` and deleted with its tile.

### Quick Capture

Quick Capture is a restart-persistent local inbox for short notes and links.
Press `⌃⌥ C` by default to open the notch directly into the capture field, type,
and press Return to save. A paste button pulls copied selected text into the
draft without saving it automatically. Captures can be searched, copied again,
pinned, opened when they are links, removed individually, or cleared together.
The shortcut is permission-free and configurable in Settings; captures remain
in Bondex Notch's local preferences and are never transmitted. On supported
Macs, the optional sparkle action uses Apple Intelligence's on-device model to
suggest a concise title, summary, explicit action items, and tags. Enhancement
is always user-triggered, can be disabled in Settings, and never saves until the
user confirms the capture.

### Siri and Shortcuts actions

Bondex exposes actions to Apple Shortcuts for creating a Quick Capture, starting
a focus timer, showing a widget, selecting a built-in Smart Profile, and turning
automatic profiles back on. These actions respect disabled widgets and features,
so a Shortcut cannot silently re-enable a preference. After installing or
updating the app, open Bondex once so macOS can refresh the available actions.

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

Live activities are off by default: turn on "Custom live activities" in
Settings › Widgets. `--live-start` says so on stderr while they are off.

Progress is a number from `0` to `1`. IDs use letters, digits, `-`, and `_` and
identify the activity across updates. Active items appear in the persistent
peek, at the top of Home, and in the reorderable Live tab. Finishing one turns
it into a normal activity-feed event and removes its signal. Signals are small
JSON files in `~/.bondex-notch/live`; the app watches the directory with a
dispatch source, so there is no polling when nothing changes. An abandoned
activity expires after 24 hours.

## First launch

A new install opens a three-page welcome: how to use the notch (hover, click to
keep it open, the global shortcut), what it should show, and a "Show me" button
that opens it. The features page says what each choice will ask macOS for —
Automation for media, the Downloads folder, the calendar, notifications, the
clipboard — and nothing that raises a permission prompt starts until it is
confirmed, so the first prompt anyone sees follows the screen that explains it. Calendar,
notification and clipboard access are requested when the choices are confirmed;
Automation and Downloads are asked for by macOS the first time the feature reads.

Closing the welcome early keeps the defaults. Installs that already have saved
preferences never see it, and it can be reopened from the menu bar's Welcome
Tour item.

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
  - A first-time user should never need to know any of that. The first time a
    browser refuses while a media site is open in it, Bondex posts one banner
    per browser launch ("Chrome is hiding what's playing"). Home's media row
    then carries a **Fix** button, and the Music tab explains the refusal in
    plain words with a button that acts on it: for Safari and Chrome-family
    browsers it brings the browser forward, next to the exact menu path, because
    that switch is the user's to flip. The refusal state is kept between scans,
    so the fix does not flicker in and out of the panel on the ticks that do
    not probe.
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
    when launched with `--enable-applescript-javascript`, and has no setting to
    make that permanent. **Reopen Dia** quits it the way ⌘Q does, so it saves
    its windows, and opens it again with the flag; the flag only reaches a fresh
    launch, which is why typing the command while Dia is still open does
    nothing. Dia reports the refusal through `OSAScript` with an
    `NSError`-style dictionary, so its message is read from the localized
    description as well as AppleScript's own keys — reading only the latter
    filed it as a transient glitch and showed nothing at all.
    `--diagnose-media` prints, per browser, how many tabs and media-site tabs
    it can see and the exact error each probe returned, without URLs or titles.
- **Reading other apps' notifications.** There is no API for this and the
  Notification Center store is SIP-protected. The "Activity" widget is a feed of
  what Bondex observes directly — track changes, completed downloads, power
  events, shelf drops — and is named accordingly.

## Permissions

All five are optional and requested only when the relevant widget is enabled.

| Permission | Needed for | Prompted by |
|---|---|---|
| Automation | Music widget, per app read | first AppleScript call |
| Files and Folders | Downloads watching | first read of `~/Downloads` |
| Notifications | Bondex posting its own alerts | Settings → Permissions |
| Calendar | Upcoming meetings and meeting profile rules | enabling Upcoming meetings |
| Paste from Other Apps (macOS 15.4+) | Clipboard history | the welcome, or Allow in the Clipboard tab |

Ad-hoc signatures change on every rebuild, so macOS treats each build as a new
app and re-prompts. Sign with a stable Developer ID identity to keep grants.

## License

Bondex Notch is free and open source under the [MIT License](../LICENSE).
Every feature is available with no trial, account, or licence key.

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

It runs against a throwaway `UserDefaults` domain and never
touches real preferences, starts none of the watchers (every state is seeded),
and uses the notched display's real notch size. The camera housing is marked
with a translucent red box: anything inside it would be invisible on a real
notched Mac. Two caveats, both
`ImageRenderer` limitations rather than app behaviour: `.onDrop` cannot be
rasterised, and `ScrollView` renders empty — `NotchRootView` and
`ScrollingStack` both degrade when `\.isRenderingOffscreen` is set.

## Known gaps

- **Gemini's hooks are not yet verified.** They are written from its own settings
  schema, but `gemini -p` hangs with no output in a non-TTY. Claude Code and Codex
  hooks are verified firing. Everything on the Bondex side remains
  agent-agnostic, so this is a question of where each agent reads its hooks from,
  not of the indicator.
- Codex's `PermissionRequest` and `PostToolUse` hooks come from its build's own
  event list but have not yet been seen firing; its approval payload is assumed
  to match Claude Code's, and falls back to "Needs your approval" if it does not.
- The opencode mark is a placeholder — a block cursor standing in until the real
  artwork is to hand.
- Downloads without a sidecar file report bytes received and live rate, not a
  percentage — no public API exposes a transfer's expected total size.
- Preferences are `UserDefaults`-backed. The proposal called for Core Data /
  SQLite; nothing yet stores enough history to need it.
- Tests cover the file watcher, the event feed, geometry and
  formatting. The AppleScript bridge and the mach/IOKit samplers are exercised
  only by running the app — neither is practical to fake without first putting
  a protocol in front of it.
