/* The panel's vocabulary, copied from the Mac app so the site can only say
   what the app says. Each block names the Swift it mirrors; change that first,
   then this. */

import { ROBOT } from './Symbol';

/* ── Tabs · NotchTab ─────────────────────────────────────── */

export type TabId =
  | 'home' | 'agents' | 'capture' | 'shortcuts' | 'music' | 'system'
  | 'buddy' | 'live' | 'files' | 'activity' | 'clipboard' | 'shelf';

/** `NotchTab.allCases`: the default widget order. */
export const TAB_ORDER: TabId[] = [
  'home', 'agents', 'capture', 'shortcuts', 'music', 'system',
  'buddy', 'live', 'files', 'activity', 'clipboard', 'shelf',
];

export const TABS: Record<TabId, { title: string; symbol: string }> = {
  home: { title: 'Home', symbol: 'square.grid.2x2.fill' },
  agents: { title: 'Agents', symbol: ROBOT },
  capture: { title: 'Capture', symbol: 'square.and.pencil' },
  shortcuts: { title: 'Shortcuts', symbol: 'bolt.square.fill' },
  music: { title: 'Music', symbol: 'music.note' },
  system: { title: 'System', symbol: 'gauge.medium' },
  buddy: { title: 'Buddy', symbol: 'leaf.fill' },
  live: { title: 'Live', symbol: 'waveform.path.ecg' },
  files: { title: 'Files', symbol: 'arrow.down.circle.fill' },
  activity: { title: 'Activity', symbol: 'bell.fill' },
  clipboard: { title: 'Clipboard', symbol: 'doc.on.clipboard.fill' },
  shelf: { title: 'Shelf', symbol: 'tray.full.fill' },
};

/* ── Wellness buddy · BuddyState, BuddyGoals, BuddyBadge ─── */

export const BUDDY_GOALS = { water: 8, breaks: 6, breakMinutes: 50 };
/** Minutes a glass of water winds the stretch back. */
export const BUDDY_WATER_CREDIT = 10;

export type BuddyMood = 'thriving' | 'content' | 'droopy' | 'wilting';

export const BUDDY_MOOD_TITLES: Record<BuddyMood, string> = {
  thriving: 'Thriving', content: 'Doing fine', droopy: 'A little droopy', wilting: 'Wilting',
};

/** `BuddyState.energy`: 1 after a break, a little under a third left when one is due. */
export const buddyEnergy = (stretchMinutes: number) =>
  Math.min(Math.max(1 - stretchMinutes / (BUDDY_GOALS.breakMinutes * 1.4), 0), 1);

/** `BuddyMood(energy:)`. */
export function buddyMood(energy: number): BuddyMood {
  if (energy >= 0.7) return 'thriving';
  if (energy >= 0.45) return 'content';
  if (energy >= 0.2) return 'droopy';
  return 'wilting';
}

export const BUDDY_BADGES = [
  { days: 1, title: 'First sprout', symbol: 'sparkle' },
  { days: 3, title: 'Seedling', symbol: 'leaf.fill' },
  { days: 7, title: 'Sapling', symbol: 'camera.macro' },
  { days: 14, title: 'In bloom', symbol: 'laurel.leading' },
  { days: 30, title: 'Evergreen', symbol: 'tree.fill' },
  { days: 100, title: 'Ancient oak', symbol: 'crown.fill' },
];

/** `BuddyWidget.duration`: "22 min", "1 h 4 min". */
export const buddyDuration = (minutes: number) =>
  minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)} h ${minutes % 60} min`;

/* ── Accents · Theme.Accent ──────────────────────────────── */

export type AccentId = 'graphite' | 'ocean' | 'sunset' | 'forest' | 'violet';

export const ACCENTS: Array<{ id: AccentId; name: string; hex: string }> = [
  { id: 'graphite', name: 'Graphite', hex: '#c7ccd4' },
  { id: 'ocean', name: 'Ocean', hex: '#4a9efa' },
  { id: 'sunset', name: 'Sunset', hex: '#fc7357' },
  { id: 'forest', name: 'Forest', hex: '#52cc8c' },
  { id: 'violet', name: 'Violet', hex: '#ad78fa' },
];

export const accentHex = (id: AccentId) => ACCENTS.find((accent) => accent.id === id)!.hex;

/* ── Agents · AgentKind ──────────────────────────────────── */

export type AgentId = 'claude' | 'codex' | 'gemini' | 'ollama';

/** Display names and tints from AgentKind; statuses from the preview renderer. */
export const AGENTS: Array<{ id: AgentId; name: string; tint: string; status: string }> = [
  { id: 'claude', name: 'Claude', tint: '#d97757', status: 'Editing PeekView.swift' },
  { id: 'codex', name: 'Codex', tint: '#6b73fa', status: 'Running tests' },
  { id: 'gemini', name: 'Gemini', tint: '#5c8cfa', status: 'Reading files' },
  { id: 'ollama', name: 'Ollama', tint: '#dbdbe0', status: 'Summarising local changes' },
];

export const agentName = (id: AgentId) => AGENTS.find((agent) => agent.id === id)!.name;
export const agentTint = (id: AgentId) => AGENTS.find((agent) => agent.id === id)!.tint;

/* ── Smart profiles · NotchProfile.defaults ──────────────── */

export type ProfileId = 'meeting' | 'work' | 'media' | 'gaming';

export interface Profile {
  id: ProfileId;
  name: string;
  symbol: string;
  order: TabId[];
  accent: AccentId;
  style: 'gradient' | 'tinted' | 'black';
  width: number;
}

export const PROFILES: Profile[] = [
  { id: 'meeting', name: 'Meeting', symbol: 'video.fill', order: ['home', 'capture', 'activity', 'system'], accent: 'violet', style: 'gradient', width: 500 },
  { id: 'work', name: 'Work', symbol: 'briefcase.fill', order: ['home', 'capture', 'shortcuts', 'clipboard', 'activity', 'system'], accent: 'ocean', style: 'gradient', width: 540 },
  { id: 'media', name: 'Media', symbol: 'play.circle.fill', order: ['home', 'music', 'system'], accent: 'sunset', style: 'tinted', width: 480 },
  { id: 'gaming', name: 'Gaming', symbol: 'gamecontroller.fill', order: ['home', 'system'], accent: 'forest', style: 'black', width: 460 },
];

/* ── Settings pages · SettingsPage ───────────────────────── */

export const SETTINGS_PAGES = [
  { id: 'general', title: 'General', subtitle: 'Interaction, keyboard, and accessibility', symbol: 'slider.horizontal.3' },
  { id: 'widgets', title: 'Widgets', subtitle: 'Choose what appears in your notch', symbol: 'square.grid.2x2.fill' },
  { id: 'profiles', title: 'Profiles', subtitle: 'Adapt widgets and appearance to your context', symbol: 'person.crop.circle.badge.clock.fill' },
  { id: 'shortcuts', title: 'Shortcuts', subtitle: 'Build your personal quick-action grid', symbol: 'bolt.square.fill' },
  { id: 'appearance', title: 'Appearance', subtitle: 'Shape, colour, material, and motion', symbol: 'paintbrush.pointed.fill' },
  { id: 'permissions', title: 'Permissions', subtitle: 'Review access used by integrations', symbol: 'lock.shield.fill' },
] as const;

/** The default Command Palette shortcut, as `HotKey.displayName` writes it. */
export const PALETTE_SHORTCUT = '⌃⌥ P';

/* ── Custom actions · the preview renderer's sample grid ─── */

export type CustomAction =
  | { id: string; title: string; kind: 'app'; icon: string }
  | { id: string; title: string; kind: 'shortcut' }
  | { id: string; title: string; kind: 'widget'; tab: TabId };

export const CUSTOM_ACTIONS: CustomAction[] = [
  { id: 'calculator', title: 'Calculator', kind: 'app', icon: '/macos-icons/calculator.png' },
  { id: 'start-my-day', title: 'Start my day', kind: 'shortcut' },
  { id: 'system', title: 'System', kind: 'widget', tab: 'system' },
  { id: 'clipboard', title: 'Clipboard', kind: 'widget', tab: 'clipboard' },
  { id: 'music', title: 'Music', kind: 'widget', tab: 'music' },
  { id: 'capture', title: 'Capture', kind: 'widget', tab: 'capture' },
];

export const actionSubtitle = (action: CustomAction) =>
  action.kind === 'app' ? 'Open app' : action.kind === 'shortcut' ? 'Run Shortcut' : 'Toggle widget';

export const actionSymbol = (action: CustomAction) =>
  action.kind === 'app' ? 'app.fill' : action.kind === 'shortcut' ? 'command' : TABS[action.tab].symbol;

/* ── Formatting · the app's string helpers ───────────────── */

/** `TimeInterval.clockString`: "6:14", "62:05". */
export function clockString(seconds: number) {
  const total = Math.max(Math.round(seconds), 0);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
}

/** `Int.compactTokenString`: "52M", "9.0M", "640K". */
export function tokenString(value: number) {
  const [scale, unit] = value >= 1e9 ? [1e9, 'B'] : value >= 1e6 ? [1e6, 'M'] : value >= 1e3 ? [1e3, 'K'] : [1, ''];
  if (!unit) return String(Math.round(value));
  const scaled = value / scale;
  return `${scaled < 10 ? scaled.toFixed(1) : Math.round(scaled)}${unit}`;
}

/** `TimeInterval.countdownString`: "3d 19h", "4h 12m", "38m". */
export function countdownString(seconds: number) {
  const total = Math.floor(Math.max(seconds, 0) / 60);
  const days = Math.floor(total / 1440);
  const hours = Math.floor((total % 1440) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${total % 60}m`;
  return `${Math.max(total % 60, 1)}m`;
}

/** `Date.shortRelativeString`: "now", "12 min ago", "2 hr ago". */
export function agoString(seconds: number) {
  if (seconds < 60) return 'now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} hr ago`;
  const days = Math.floor(seconds / 86400);
  return days === 1 ? '1 day ago' : `${days} days ago`;
}

export const usdString = (value: number) =>
  `$${value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/** `Text(date, style: .time)`. */
export const timeOfDay = (date: Date) =>
  date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });

/* ── Agent usage · PreviewRenderer.sampleAgentUsage ──────── */

export type UsageRange = 'today' | 'week' | 'month';
export const RANGES: Array<{ id: UsageRange; short: string; title: string }> = [
  { id: 'today', short: '1D', title: 'Today' },
  { id: 'week', short: '7D', title: '7 Days' },
  { id: 'month', short: '30D', title: '30 Days' },
];

export type Provider = 'claude' | 'codex';
export const PROVIDERS: Provider[] = ['claude', 'codex'];

export const USAGE_PROVIDERS: Array<{
  id: Provider;
  model: string;
  plan: string;
  /** Seconds before the page loaded that the limits were read. */
  observedAgo: number;
  limits: Array<{ label: string; used: number; window: number; resets: number }>;
}> = [
  {
    id: 'claude', model: 'Opus 5.5', plan: 'Pro', observedAgo: 240,
    limits: [
      { label: 'Session', used: 64, window: 300 * 60, resets: 1.6 * 3600 },
      { label: 'Week', used: 34, window: 7 * 86400, resets: 3 * 86400 + 19 * 3600 },
    ],
  },
  {
    id: 'codex', model: 'GPT-6.1 Sol', plan: 'Plus', observedAgo: 2 * 3600,
    limits: [{ label: 'Week', used: 5, window: 7 * 86400, resets: 5 * 86400 }],
  },
];

export type TrendBar = { claude: number; codex: number; start: Date };
export type RangeSummary = {
  claude: { tokens: number; cost: number };
  codex: { tokens: number; cost: number };
  trend: TrendBar[];
};

const claudeByHour = [0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 6, 5, 2, 4, 7, 6, 3, 2, 1, 0, 0, 0, 0, 0];
const codexByHour = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 2, 1, 1, 3, 2, 1, 0, 0, 0, 0];

/** The renderer's busy day of Claude Code and Codex, relative to `now`. */
export function usageSummaries(now: Date): Record<UsageRange, RangeSummary> {
  const today = new Date(now);
  today.setHours(0, 0, 0, 0);

  const days = (count: number): RangeSummary => {
    const trend: TrendBar[] = [];
    for (let offset = 0; offset < count; offset += 1) {
      const start = new Date(today);
      start.setDate(today.getDate() + offset - count + 1);
      const weekend = start.getDay() === 0 || start.getDay() === 6;
      const weight = weekend ? 1 : 4 + ((offset * 7) % 5);
      trend.push({ claude: weight * 9e6, codex: weight * 2e6, start });
    }
    const weights = trend.reduce((sum, bar) => sum + bar.claude / 9e6, 0);
    return { claude: { tokens: weights * 9e6, cost: weights * 1.9 }, codex: { tokens: weights * 2e6, cost: weights * 0.6 }, trend };
  };

  return {
    today: {
      claude: { tokens: 40e6, cost: 8.61 },
      codex: { tokens: 12e6, cost: 3.55 },
      trend: claudeByHour.map((claude, hour) => {
        const start = new Date(today);
        start.setHours(hour);
        return { claude: claude * 1e6, codex: codexByHour[hour] * 1e6, start };
      }),
    },
    week: days(7),
    month: days(30),
  };
}

/** Today's lists. The renderer seeds them for today only. */
export const USAGE_BREAKDOWNS: Record<'projects' | 'models', Array<{ name: string; agent: Provider; tokens: number; cost: number }>> = {
  projects: [
    { name: 'Bondex-Notch', agent: 'claude', tokens: 28e6, cost: 6.12 },
    { name: 'Portfolio', agent: 'codex', tokens: 13e6, cost: 3.55 },
    { name: 'Apsara Talent', agent: 'claude', tokens: 9e6, cost: 1.98 },
    { name: 'Scratch', agent: 'claude', tokens: 2e6, cost: 0.51 },
  ],
  models: [
    { name: 'Opus 5.5', agent: 'claude', tokens: 35e6, cost: 7.94 },
    { name: 'GPT-6.1 Sol', agent: 'codex', tokens: 13e6, cost: 3.55 },
    { name: 'Sonnet 5.5', agent: 'claude', tokens: 4e6, cost: 0.67 },
  ],
};

/** Sessions, newest first. `ago` is seconds before the page loaded. */
export const USAGE_SESSIONS: Array<{ id: string; agent: Provider; project: string; model: string; ago: number }> = [
  { id: 'claude:1', agent: 'claude', project: 'Bondex-Notch', model: 'Opus 5.5', ago: 20 },
  { id: 'codex:1', agent: 'codex', project: 'Portfolio', model: 'GPT-6.1 Sol', ago: 2 * 3600 },
  { id: 'claude:2', agent: 'claude', project: 'Apsara Talent', model: 'Sonnet 5.5', ago: 4 * 3600 },
];

/** The session Home names a working agent by: active in the last 15 minutes. */
export function liveSession(agent: AgentId, elapsedSincePageLoad: number) {
  return USAGE_SESSIONS.find((session) => session.agent === agent && session.ago + elapsedSincePageLoad < 15 * 60);
}

/* ── Command palette · CommandPaletteCommand ─────────────── */

export interface Command {
  id: string;
  title: string;
  subtitle: string;
  symbol: string;
  category: string;
  keywords: string[];
  priority: number;
}

/** `CommandPaletteCommand.search`, scoring and all. */
export function searchCommands(query: string, commands: Command[], limit = 6) {
  const terms = query.split(/\s+/).filter(Boolean).map((term) => term.toLowerCase());
  return commands
    .flatMap((command): Array<[Command, number]> => {
      if (terms.length === 0) return [[command, -command.priority]];
      const title = command.title.toLowerCase();
      const subtitle = command.subtitle.toLowerCase();
      const category = command.category.toLowerCase();
      const keywords = command.keywords.map((keyword) => keyword.toLowerCase());
      let score = -command.priority;
      for (const term of terms) {
        if (title === term) score += 140;
        else if (title.startsWith(term)) score += 100;
        else if (title.includes(term)) score += 72;
        else if (subtitle.includes(term)) score += 42;
        else if (category.includes(term) || keywords.some((keyword) => keyword.includes(term))) score += 28;
        else return [];
      }
      return [[command, score]];
    })
    .sort((a, b) => b[1] - a[1] || a[0].priority - b[0].priority || a[0].title.localeCompare(b[0].title, 'en', { numeric: true }))
    .slice(0, Math.max(limit, 0))
    .map(([command]) => command);
}
