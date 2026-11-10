/* Every claim the page makes, in one place.
   The copy is deliberately conservative about what a Mac app can actually do —
   see the FAQ. Change it here, not in the components. */

export type FeatureIcon =
  | 'music'
  | 'browser'
  | 'agent'
  | 'capture'
  | 'clipboard'
  | 'shortcuts'
  | 'focus'
  | 'buddy'
  | 'profiles'
  | 'privacy'
  | 'live'
  | 'files'
  | 'system'
  | 'bell'
  | 'tray'
  | 'tune'
  | 'bolt';

export interface Feature {
  icon: FeatureIcon;
  title: string;
  body: string;
}

export const features: Feature[] = [
  {
    icon: 'music',
    title: 'Music',
    body:
      "Track, artist, album art and a scrubbing progress bar for Music and " +
      "Spotify — with transport controls that don't steal focus from what " +
      "you're typing.",
  },
  {
    icon: 'browser',
    title: 'Browser audio',
    body:
      'See what is playing in Safari and Chromium tabs, including YouTube, ' +
      'YouTube Music, SoundCloud and Twitch — with controls when the site exposes them.',
  },
  {
    icon: 'agent',
    title: 'Agent activity',
    body:
      'Know when Codex, Claude Code, Gemini, Ollama or another CLI agent is ' +
      'working, how long it has been running, and which project and model it is on. ' +
      'The notch turns amber when one stops for your approval, and Claude Code, ' +
      'Codex and Gemini CLI are set up with one click.',
  },
  {
    icon: 'agent',
    title: 'Agent usage',
    body:
      'An Agents tab for Claude Code and Codex: plan limits with reset countdowns, ' +
      'API-equivalent spend over 1, 7 or 30 days, recent sessions and a trend by ' +
      'project or model — read from local logs, with no sign-in.',
  },
  {
    icon: 'capture',
    title: 'Quick Capture',
    body:
      'Save a thought or link without leaving your current app. Search, pin and ' +
      'copy captures later, with optional user-triggered on-device Apple Intelligence ' +
      'enhancement on supported macOS 26 Macs.',
  },
  {
    icon: 'clipboard',
    title: 'Clipboard history',
    body:
      'Keep text, links and images from this session close at hand. Pause capture, ' +
      'search or pin an item; concealed and transient clipboard content is ignored, ' +
      'history is never written to disk, and nothing is read until you allow it.',
  },
  {
    icon: 'shortcuts',
    title: 'Actions and shortcuts',
    body:
      'Build a personal action grid for opening apps, running Apple Shortcuts and ' +
      'showing the widget you need. Global shortcuts, any combination you record, ' +
      'open the panel, Capture or the command palette.',
  },
  {
    icon: 'focus',
    title: 'Focus and meetings',
    body:
      'Run a restart-safe focus timer from 1 to 180 minutes, and optionally see the ' +
      'next calendar event with a countdown and one-click Zoom, Meet, Teams or Webex link.',
  },
  {
    icon: 'buddy',
    title: 'Wellness buddy',
    body:
      'A little plant that wilts the longer you work without a break and perks up ' +
      'when you step away or drink water. Daily water and break goals, streak badges, ' +
      'and a quiet nudge beside the notch instead of an alert — read only from how ' +
      'long since your last keystroke, with no permission.',
  },
  {
    icon: 'profiles',
    title: 'Smart profiles',
    body:
      'Switch the notch for Work, Meeting, Media or Gaming — manually or with rules ' +
      'for the active app, time, power source, connected displays and meetings. The ' +
      'command palette puts every action in one search.',
  },
  {
    icon: 'live',
    title: 'Custom live activities',
    body:
      'Send progress from a script, Shortcut, build tool or terminal. Active ' +
      'jobs stay in the peek and finish directly into your activity feed.',
  },
  {
    icon: 'files',
    title: 'File activity',
    body:
      'Watches your Downloads folder and reports transfers as they land, with ' +
      'live throughput. Click through to reveal anything in Finder.',
  },
  {
    icon: 'system',
    title: 'System',
    body:
      'CPU load, memory pressure, battery and real network throughput — plus connected ' +
      'headphone, keyboard, mouse and trackpad batteries when macOS exposes them.',
  },
  {
    icon: 'privacy',
    title: 'Hardware HUD + privacy',
    body:
      'See volume, display brightness, keyboard brightness and battery changes beside ' +
      'the notch. Camera and microphone activity indicators work without recording or ' +
      'asking for camera or microphone access.',
  },
  {
    icon: 'bell',
    title: 'Activity feed',
    body:
      'A running log of what changed: tracks, finished downloads, power ' +
      'events, shelf drops. Transient events also flash as a banner beside ' +
      'the notch.',
  },
  {
    icon: 'tray',
    title: 'Drop shelf',
    body:
      'Drag files onto the notch to park them, then drag them back out ' +
      'anywhere. Nothing is copied: the shelf holds your real files, follows ' +
      'them when they move, and is still there after a restart.',
  },
  {
    icon: 'tune',
    title: 'Make it yours',
    body:
      'Tune width, opacity, corners, top flares, rim, shadow and animation speed. ' +
      'Choose a preset or custom accent and reorder every tab.',
  },
  {
    icon: 'bolt',
    title: 'Native automation',
    body:
      'Use App Intents in Apple Shortcuts to switch profiles, capture a thought, start ' +
      'a focus timer, show a widget or change automatic profile mode — all in a native ' +
      'Swift and SwiftUI app with no Electron or web view.',
  },
];

/* ── Panel states ─────────────────────────────────────────
   NotchGeometry's real sizes in points, drawn at 0.4×: the 185 × 32pt notch
   of a 14-inch MacBook Pro, the 305pt peek that carries playback or one
   working agent, and the 520pt default panel at the height of a typical Home
   (one agent, playback, the focus chip). Corner radii are Theme's 10, 15 and
   20pt; the fillets are its 11pt flare. The diagram is the notch, not an
   illustration of it. */

export const STATE_SCALE = 0.4;

export interface PanelState {
  id: 'collapsed' | 'peek' | 'expanded';
  title: string;
  body: string;
  /** Points, before scaling. */
  width: number;
  height: number;
  radius: number;
}

export const panelStates: PanelState[] = [
  {
    id: 'collapsed',
    title: 'Collapsed',
    body:
      'Exactly the size of your hardware notch, and completely invisible ' +
      'against it. Bondex is doing nothing to your screen.',
    width: 185,
    height: 32,
    radius: 10,
  },
  {
    id: 'peek',
    title: 'Peek',
    body:
      'When something needs context — a track, agent, focus timer, meeting, break ' +
      'reminder, hardware change or privacy signal — a thin strip grows beside the ' +
      'notch. Never over it.',
    width: 305,
    height: 32,
    radius: 15,
  },
  {
    id: 'expanded',
    title: 'Expanded',
    body:
      "Move the pointer to the notch and the full panel springs down. Move " +
      "away and it's gone. Click to pin it open while you work.",
    width: 520,
    height: 245,
    radius: 20,
  },
];

/* ── Pricing ──────────────────────────────────────────────
   Bondex Notch is free and open source under the MIT License. */

export interface Plan {
  name: string;
  price: string;
  cadence?: string;
  note: string;
  items: string[];
  featured?: boolean;
  badge?: string;
  /** A plan with no call to action is not for sale yet. */
  cta?: { label: string; href: string; style: 'solid' | 'ghost' };
  unavailable?: string;
}

export const plans: Plan[] = [
  {
    name: 'Bondex Notch',
    price: 'Free',
    cadence: 'MIT licensed',
    note: 'The complete app, free for everyone. No trial, account, or licence key.',
    featured: true,
    badge: 'Open source',
    items: [
      'Music and supported browser playback',
      'Agent activity for Codex, Claude, Gemini, Ollama and custom agents',
      'Claude Code and Codex usage: plan limits, spend and sessions',
      'Custom live activities from scripts and Shortcuts',
      'Quick Capture and session-only clipboard history',
      'Focus timer and optional upcoming meetings',
      'Wellness buddy with water and break goals',
      'Custom actions, command palette and Apple Shortcuts actions',
      'Smart profiles with automatic rules',
      'System metrics, connected-device batteries and hardware HUD',
      'Privacy indicators and activity feed',
      'Hover, peek and expand behaviour',
      'File activity and live downloads',
      'Drag-and-drop file shelf',
      'Every theme and appearance control',
      'Full source code on GitHub',
    ],
    cta: { label: 'Download for Mac', href: '/download/', style: 'solid' },
  },
];

/* ── FAQ ──────────────────────────────────────────────────
   `body` is JSX in the component so `code` and emphasis survive. Keeping the
   questions here means the order and the open-by-default one live together. */

export const faqIds = [
  'music-apps',
  'notifications',
  'memory',
  'permissions',
  'displays',
] as const;

export type FaqId = (typeof faqIds)[number];
