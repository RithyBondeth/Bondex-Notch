/* Every claim the page makes, in one place.
   The copy is deliberately conservative about what a Mac app can actually do —
   see the FAQ. Change it here, not in the components. */

export type FeatureIcon =
  | 'music'
  | 'browser'
  | 'agent'
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
  /** Shown as a corner tag. Omit for features in the free tier. */
  tier?: 'Pro';
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
    tier: 'Pro',
  },
  {
    icon: 'system',
    title: 'System',
    body:
      'CPU load, memory pressure, battery level and time remaining, and real ' +
      'network throughput — sampled straight from the kernel, not estimated.',
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
    tier: 'Pro',
  },
  {
    icon: 'tune',
    title: 'Make it yours',
    body:
      'Tune width, opacity, corners, top flares, rim, shadow and animation speed. ' +
      'Choose a preset or custom accent and reorder every tab.',
    tier: 'Pro',
  },
  {
    icon: 'bolt',
    title: 'Genuinely light',
    body:
      'Swift and SwiftUI throughout, no Electron and no web view. Widgets you ' +
      'switch off stop their background service instead of continuing unseen.',
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
      'When something is live — a track playing, an agent working, or a build ' +
      'running — a thin strip grows beside the notch. Never over it.',
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
    name: 'Free',
    price: '$0',
    note: 'Everything you need to live in the notch.',
    items: [
      'Music and supported browser playback',
      'Agent activity for Codex, Claude, Gemini, Ollama and custom agents',
      'Custom live activities from scripts and Shortcuts',
      'System widget — CPU, memory, battery, network',
      'Activity feed',
      'Hover, peek and expand behaviour',
      'Graphite theme',
    ],
    cta: { label: 'Get early access', href: '#contact', style: 'ghost' },
  },
  {
    name: 'Pro',
    price: '$14.99',
    cadence: 'one-time',
    note: 'Everything in Free, plus:',
    featured: true,
    badge: 'Most popular',
    items: [
      'File activity widget',
      'Drop shelf',
      'All accent themes and deep appearance controls',
      'Lifetime license, no account',
    ],
    cta: { label: 'Buy Pro', href: '/checkout', style: 'solid' },
  },
  {
    name: 'AI add-on',
    price: '$4',
    cadence: '/month',
    note: 'Optional. Cancel whenever.',
    items: [
      'Notification summarisation',
      'Smart replies',
      'Calendar assistance',
      'Requires a Pro license',
    ],
    unavailable: 'On the roadmap',
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
