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
      'working, what it is doing, and how long it has been running.',
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
      'search or pin an item; concealed and transient clipboard content is ignored ' +
      'and history is never written to disk.',
  },
  {
    icon: 'shortcuts',
    title: 'Actions and shortcuts',
    body:
      'Build a personal action grid for opening apps, running Apple Shortcuts and ' +
      'showing the widget you need. Global shortcuts can open the panel, Capture or ' +
      'the command palette.',
  },
  {
    icon: 'focus',
    title: 'Focus and meetings',
    body:
      'Run a restart-safe focus timer from 1 to 180 minutes, and optionally see the ' +
      'next calendar event with a countdown and one-click Zoom, Meet, Teams or Webex link.',
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
      'anywhere. Nothing is copied — the shelf holds references to your real ' +
      'files.',
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
   `width` and `height` are the real panel dimensions the app uses, scaled
   down by a constant. The diagram is the notch, not an illustration of it. */

export interface PanelState {
  id: 'collapsed' | 'peek' | 'expanded';
  title: string;
  body: string;
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
    width: 74,
    height: 14,
    radius: 6,
  },
  {
    id: 'peek',
    title: 'Peek',
    body:
      'When something needs context — a track, agent, focus timer, meeting, hardware ' +
      'change or privacy signal — a thin strip grows beside the notch. Never over it.',
    width: 128,
    height: 16,
    radius: 6,
  },
  {
    id: 'expanded',
    title: 'Expanded',
    body:
      "Move the pointer to the notch and the full panel springs down. Move " +
      "away and it's gone. Click to pin it open while you work.",
    width: 216,
    height: 78,
    radius: 14,
  },
];

/* ── Pricing ──────────────────────────────────────────────
   Figures are provisional; see the README before publishing. */

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
    price: '$14.99',
    cadence: 'one-time',
    note: 'Try the complete app free for 24 hours. Then purchase once to keep using it.',
    featured: true,
    badge: '24-hour full trial',
    items: [
      'Music and supported browser playback',
      'Agent activity for Codex, Claude, Gemini, Ollama and custom agents',
      'Custom live activities from scripts and Shortcuts',
      'Quick Capture and session-only clipboard history',
      'Focus timer and optional upcoming meetings',
      'Custom actions, command palette and Apple Shortcuts actions',
      'Smart profiles with automatic rules',
      'System metrics, connected-device batteries and hardware HUD',
      'Privacy indicators and activity feed',
      'Hover, peek and expand behaviour',
      'File activity and live downloads',
      'Drag-and-drop file shelf',
      'Every theme and appearance control',
      'Lifetime licence, no feature tiers',
    ],
    cta: { label: 'Buy Bondex Notch', href: '/checkout', style: 'solid' },
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
