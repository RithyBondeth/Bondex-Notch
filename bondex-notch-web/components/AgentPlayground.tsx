'use client';

import Image from 'next/image';
import { type CSSProperties, type DragEvent, useEffect, useState } from 'react';

type AgentId = 'claude' | 'codex' | 'gemini' | 'ollama';
type TabId = 'home' | 'agents' | 'capture' | 'shortcuts' | 'music' | 'system' | 'live' | 'files' | 'activity' | 'clipboard' | 'shelf';
type Accent = 'ocean' | 'violet' | 'forest';
type Profile = 'Work' | 'Meeting' | 'Media' | 'Gaming';
type UsageRange = '1D' | '7D' | '30D';
type Breakdown = 'Trend' | 'Projects' | 'Models';

/* Stand-ins for the SF Symbols the app's card headers use. */
const cardIcons = {
  spending: (
    <svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.6" fill="none" stroke="currentColor" strokeWidth="1.4" /><path d="M10 5.9c-.4-.6-1.1-.9-2-.9-1.2 0-2 .6-2 1.5 0 2 4.1 1 4.1 3 0 .9-.9 1.5-2.1 1.5-.9 0-1.7-.4-2.1-1M8 3.8v1.2M8 11v1.2" fill="none" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" /></svg>
  ),
  sessions: (
    <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M1 8.5h3l1.6-4 2.6 8 2-6.2 1 2.2H15" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" /></svg>
  ),
  Trend: (
    <svg viewBox="0 0 16 16" aria-hidden="true"><rect x="1.5" y="8" width="3.4" height="6" rx="1" /><rect x="6.3" y="4.5" width="3.4" height="9.5" rx="1" /><rect x="11.1" y="2" width="3.4" height="12" rx="1" /></svg>
  ),
  Projects: (
    <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M1.5 4.2c0-.8.6-1.4 1.4-1.4h3.4l1.6 1.7h5.2c.8 0 1.4.6 1.4 1.4v6.4c0 .8-.6 1.4-1.4 1.4H2.9c-.8 0-1.4-.6-1.4-1.4Z" /></svg>
  ),
  Models: (
    <svg viewBox="0 0 16 16" aria-hidden="true"><rect x="3.5" y="3.5" width="9" height="9" rx="1.8" fill="none" stroke="currentColor" strokeWidth="1.3" /><rect x="6" y="6" width="4" height="4" rx=".6" /><path d="M6 1.5v2M10 1.5v2M6 12.5v2M10 12.5v2M1.5 6h2M1.5 10h2M12.5 6h2M12.5 10h2" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" /></svg>
  ),
};

const robotIcon = (
  <svg viewBox="0 0 16 16" aria-hidden="true" className="real-tab-svg">
    <circle cx="8" cy="2.2" r="1.1" />
    <rect x="7.4" y="2.6" width="1.2" height="2" />
    <rect x="3" y="4.5" width="10" height="8" rx="2.4" />
    <rect x="1" y="7.2" width="1.4" height="3" rx=".6" />
    <rect x="13.6" y="7.2" width="1.4" height="3" rx=".6" />
    <circle cx="6" cy="8.2" r="1.1" fill="#000" />
    <circle cx="10" cy="8.2" r="1.1" fill="#000" />
    <rect x="6" y="10.4" width="4" height=".9" rx=".45" fill="#000" />
  </svg>
);

const tabs: Array<{ id: TabId; label: string; icon: React.ReactNode }> = [
  { id: 'home', label: 'Home', icon: '⌘' },
  { id: 'agents', label: 'Agents', icon: robotIcon },
  { id: 'capture', label: 'Capture', icon: '✎' },
  { id: 'shortcuts', label: 'Shortcuts', icon: '▦' },
  { id: 'music', label: 'Music', icon: '♪' },
  { id: 'system', label: 'System', icon: '◴' },
  { id: 'live', label: 'Live', icon: '⌁' },
  { id: 'files', label: 'Files', icon: '↓' },
  { id: 'activity', label: 'Activity', icon: '●' },
  { id: 'clipboard', label: 'Clipboard', icon: '▤' },
  { id: 'shelf', label: 'Shelf', icon: '▱' },
];

/* Mirrors the app's AgentKind: display names, tints and the Home/preview
   sample statuses. Claude's session is recent enough for Home to name its
   project and model; Codex's newest session is hours old, so it gets none. */
const agents: Array<{ id: AgentId; name: string; tint: string; status: string; project?: string; model?: string }> = [
  { id: 'claude', name: 'Claude', tint: '#d97757', status: 'Editing PeekView.swift', project: 'Bondex-Notch', model: 'Opus 5.5' },
  { id: 'codex', name: 'Codex', tint: '#6b73fa', status: 'Running tests' },
  { id: 'gemini', name: 'Gemini', tint: '#5c8cfa', status: 'Reading files' },
  { id: 'ollama', name: 'Ollama', tint: '#dbdbe0', status: 'Summarising local changes' },
];
const tintOf = (id: AgentId) => agents.find((agent) => agent.id === id)!.tint;

/* The Agents tab, seeded with the same sample day the app's preview renderer
   uses. The app reads these figures from the agents' own logs on the Mac. */
type Provider = 'claude' | 'codex';
const providers: Provider[] = ['claude', 'codex'];

const usageProviders: Array<{
  id: Provider;
  model: string;
  plan: string;
  /** Seconds since the limits were read; older than 15 minutes is labelled. */
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

type TrendBar = { claude: number; codex: number; label: string };
type RangeSummary = { claude: { tokens: number; cost: number }; codex: { tokens: number; cost: number }; trend: TrendBar[] };

const claudeByHour = [0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 6, 5, 2, 4, 7, 6, 3, 2, 1, 0, 0, 0, 0, 0];
const codexByHour = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 2, 1, 1, 3, 2, 1, 0, 0, 0, 0];
const hourLabel = (hour: number) => `${hour % 12 === 0 ? 12 : hour % 12}${hour < 12 ? 'a' : 'p'}`;

function daySummary(count: number): RangeSummary {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const trend: TrendBar[] = [];
  for (let offset = 0; offset < count; offset += 1) {
    const start = new Date(today);
    start.setDate(today.getDate() + offset - count + 1);
    const weekend = start.getDay() === 0 || start.getDay() === 6;
    const weight = weekend ? 1 : 4 + ((offset * 7) % 5);
    const label = count === 7 ? 'SMTWTFS'[start.getDay()] : offset % 5 === 0 ? String(start.getDate()) : '';
    trend.push({ claude: weight * 9e6, codex: weight * 2e6, label });
  }
  const weights = trend.map((bar) => bar.claude / 9e6);
  const sum = weights.reduce((a, b) => a + b, 0);
  return {
    claude: { tokens: sum * 9e6, cost: sum * 1.9 },
    codex: { tokens: sum * 2e6, cost: sum * 0.6 },
    trend,
  };
}

const usageSummaries: Record<UsageRange, RangeSummary> = {
  '1D': {
    claude: { tokens: 40e6, cost: 8.61 },
    codex: { tokens: 12e6, cost: 3.55 },
    trend: claudeByHour.map((claude, hour) => ({ claude: claude * 1e6, codex: codexByHour[hour] * 1e6, label: hour % 6 === 0 ? hourLabel(hour) : '' })),
  },
  '7D': daySummary(7),
  '30D': daySummary(30),
};

/* Today's lists. The app's preview only seeds them for today, so longer
   ranges scale them by that range's tokens. */
const usageBreakdowns: Record<Exclude<Breakdown, 'Trend'>, Array<{ name: string; agent: Provider; tokens: number; cost: number }>> = {
  Projects: [
    { name: 'Bondex-Notch', agent: 'claude', tokens: 28e6, cost: 6.12 },
    { name: 'Portfolio', agent: 'codex', tokens: 13e6, cost: 3.55 },
    { name: 'Apsara Talent', agent: 'claude', tokens: 9e6, cost: 1.98 },
    { name: 'Scratch', agent: 'claude', tokens: 2e6, cost: 0.51 },
  ],
  Models: [
    { name: 'Opus 5.5', agent: 'claude', tokens: 35e6, cost: 7.94 },
    { name: 'GPT-6.1 Sol', agent: 'codex', tokens: 13e6, cost: 3.55 },
    { name: 'Sonnet 5.5', agent: 'claude', tokens: 4e6, cost: 0.67 },
  ],
};

const usageSessions: Array<{ id: string; agent: Provider; project: string; model: string; ago: number }> = [
  { id: 'claude:1', agent: 'claude', project: 'Bondex-Notch', model: 'Opus 5.5', ago: 20 },
  { id: 'codex:1', agent: 'codex', project: 'Portfolio', model: 'GPT-6.1 Sol', ago: 2 * 3600 },
  { id: 'claude:2', agent: 'claude', project: 'Apsara Talent', model: 'Sonnet 5.5', ago: 4 * 3600 },
];

/** "52M", "9.0M", "640K" — the app's compactTokenString. */
function formatTokens(value: number) {
  const unit = value >= 1e9 ? [1e9, 'B'] as const : value >= 1e6 ? [1e6, 'M'] as const : value >= 1e3 ? [1e3, 'K'] as const : [1, ''] as const;
  const scaled = value / unit[0];
  return `${scaled < 10 && unit[1] ? scaled.toFixed(1) : Math.round(scaled)}${unit[1]}`;
}

/** "3d 19h", "4h 12m", "38m" — the app's countdownString. */
function formatCountdown(seconds: number) {
  const total = Math.floor(Math.max(seconds, 0) / 60);
  const days = Math.floor(total / 1440);
  const hours = Math.floor((total % 1440) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${total % 60}m`;
  return `${Math.max(total % 60, 1)}m`;
}

/** "now", "12 min ago", "2 hr ago" — the app's shortRelativeString. */
function formatAgo(seconds: number) {
  if (seconds < 60) return 'now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} hr ago`;
  const days = Math.floor(seconds / 86400);
  return days === 1 ? '1 day ago' : `${days} days ago`;
}

function formatUsd(value: number) {
  return `$${value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** "6:14" — the app's clockString for agent run time. */
function formatClock(totalSeconds: number) {
  return `${Math.floor(totalSeconds / 60)}:${(totalSeconds % 60).toString().padStart(2, '0')}`;
}

const tracks = [
  { title: 'Blinding Lights', artist: 'The Weeknd', album: 'After Hours', source: 'Spotify', duration: 200, artwork: '/album-art/after-hours.jpg' },
  { title: 'Die With A Smile', artist: 'Lady Gaga & Bruno Mars', album: 'Die With A Smile', source: 'Spotify', duration: 251, artwork: '/album-art/die-with-a-smile.jpg' },
];

const claudeCodePixels = [
  '..XXXXXXXXXXXX..', '..XXXXXXXXXXXX..', '..XX.XXXXXX.XX..', '..XX.XXXXXX.XX..',
  'XXXXXXXXXXXXXXXX', 'XXXXXXXXXXXXXXXX', '..XXXXXXXXXXXX..', '..XXXXXXXXXXXX..',
  '...X.X....X.X...', '...X.X....X.X...',
].join('');

const accentColors: Record<Accent, string> = {
  ocean: '#4a9efa',
  violet: '#ad78fa',
  forest: '#52cc8c',
};

function ClaudeCodeMark() {
  return (
    <span className="claude-code-mark" aria-hidden="true">
      {[...claudeCodePixels].map((pixel, index) => (
        <i className={pixel === 'X' ? 'is-on' : undefined} key={index} />
      ))}
    </span>
  );
}

/** The agent's bare mark, tinted, as the app's PixelMark draws it. */
function PixelMark({ id }: { id: AgentId }) {
  const tint = tintOf(id);
  if (id === 'claude') return <span className="pixel-mark" style={{ color: tint }}><ClaudeCodeMark /></span>;
  if (id === 'codex') {
    return (
      <svg className="pixel-mark" viewBox="0 0 1 1" aria-hidden="true">
        <path d="M.24 .24 L.48 .48 L.24 .72 M.56 .72 L.82 .72" fill="none" stroke={tint} strokeWidth=".13" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    );
  }
  if (id === 'gemini') {
    return (
      <svg className="pixel-mark" viewBox="0 0 1 1" aria-hidden="true">
        <path d="M.5 .04 Q.5 .5 .96 .5 Q.5 .5 .5 .96 Q.5 .5 .04 .5 Q.5 .5 .5 .04 Z" fill={tint} />
      </svg>
    );
  }
  return <span className="pixel-mark pixel-mark--masked" style={{ background: tint, '--agent-mark': `url('/agent-icons/${id}.svg')` } as CSSProperties} aria-hidden="true" />;
}

/** The app's AgentOrb: the mark inside a ring whose arc sweeps while it works. */
function AgentOrb({ id, size }: { id: AgentId; size: number }) {
  return (
    <span className="app-orb" style={{ '--orb': `${size}px`, '--tint': tintOf(id) } as CSSProperties} aria-hidden="true">
      <i />
      <PixelMark id={id} />
    </span>
  );
}

function formatTime(totalSeconds: number) {
  const minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0');
  const seconds = (totalSeconds % 60).toString().padStart(2, '0');
  return `${minutes}:${seconds}`;
}

export default function AgentPlayground() {
  const [tab, setTab] = useState<TabId>('home');
  const [accent, setAccent] = useState<Accent>('ocean');
  const [active, setActive] = useState<Set<AgentId>>(() => new Set(['claude', 'codex']));
  const [elapsed, setElapsed] = useState<Record<AgentId, number>>({ claude: 374, codex: 52, gemini: 0, ollama: 0 });
  const [buildState, setBuildState] = useState<'idle' | 'running' | 'done'>('running');
  const [buildProgress, setBuildProgress] = useState(72);
  const [musicPlaying, setMusicPlaying] = useState(true);
  const [musicPosition, setMusicPosition] = useState(78);
  const [trackIndex, setTrackIndex] = useState(0);
  const [downloadState, setDownloadState] = useState<'idle' | 'running' | 'done'>('idle');
  const [downloadBytes, setDownloadBytes] = useState(0);
  const [shelfItems, setShelfItems] = useState(['Launch brief.pdf', 'Hero artwork.png']);
  const [isDropping, setIsDropping] = useState(false);
  const [systemTick, setSystemTick] = useState(0);
  const [events, setEvents] = useState([
    { id: 1, icon: '↓', title: 'design-review.sketch', detail: 'Download complete · 184 MB', time: 'Just now' },
    { id: 2, icon: '♪', title: 'Blinding Lights', detail: 'The Weeknd · Spotify', time: '2m' },
  ]);
  const [captureDraft, setCaptureDraft] = useState('');
  const [captures, setCaptures] = useState([
    { id: 1, text: 'Review the launch checklist at 3 PM', meta: 'Note · pinned' },
    { id: 2, text: 'https://bondex.app/launch', meta: 'Link · today' },
  ]);
  const [clipboardPaused, setClipboardPaused] = useState(false);
  const [clipboardSearch, setClipboardSearch] = useState('');
  const [clipboardItems] = useState([
    { id: 1, text: 'Ship the quiet details.', meta: 'Text · just now' },
    { id: 2, text: 'https://developer.apple.com/shortcuts/', meta: 'Link · 2m' },
    { id: 3, text: 'Launch artwork.png', meta: 'Image · 6m' },
  ]);
  const [shortcutFeedback, setShortcutFeedback] = useState('Ready');
  const [profile, setProfile] = useState<Profile>('Work');
  const [focusSeconds, setFocusSeconds] = useState(25 * 60);
  const [focusRunning, setFocusRunning] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [commandQuery, setCommandQuery] = useState('');
  const [usageRange, setUsageRange] = useState<UsageRange>('1D');
  const [breakdown, setBreakdown] = useState<Breakdown>('Trend');

  const track = tracks[trackIndex];
  const cpu = [23, 31, 27, 42, 35][systemTick % 5];
  const memory = [67, 69, 71, 70, 68][systemTick % 5];
  const down = ['3.2 MB/s', '4.8 MB/s', '2.7 MB/s', '5.1 MB/s'][systemTick % 4];

  useEffect(() => {
    const timer = window.setInterval(() => {
      setElapsed((current) => {
        const next = { ...current };
        active.forEach((id) => { next[id] += 1; });
        return next;
      });
      setSystemTick((current) => current + 1);
    }, 1000);
    return () => window.clearInterval(timer);
  }, [active]);

  useEffect(() => {
    if (!musicPlaying) return;
    const timer = window.setInterval(() => setMusicPosition((current) => (current + 1) % track.duration), 1000);
    return () => window.clearInterval(timer);
  }, [musicPlaying, track.duration]);

  useEffect(() => {
    if (buildState !== 'running') return;
    const timer = window.setInterval(() => setBuildProgress((current) => Math.min(current + 1, 99)), 110);
    const completion = window.setTimeout(() => {
      setBuildProgress(100);
      setBuildState('done');
      setEvents((current) => [
        { id: Date.now(), icon: '✓', title: 'Building release finished', detail: 'Build succeeded', time: 'Now' },
        ...current,
      ]);
    }, 3200);
    return () => { window.clearInterval(timer); window.clearTimeout(completion); };
  }, [buildState]);

  useEffect(() => {
    if (downloadState !== 'running') return;
    const timer = window.setInterval(() => setDownloadBytes((current) => Math.min(current + 64, 4096)), 90);
    const completion = window.setTimeout(() => {
      setDownloadBytes(4096);
      setDownloadState('done');
      setEvents((current) => [
        { id: Date.now(), icon: '↓', title: 'Xcode_26.xip', detail: 'Download complete · 4.1 GB', time: 'Now' },
        ...current,
      ]);
    }, 5800);
    return () => { window.clearInterval(timer); window.clearTimeout(completion); };
  }, [downloadState]);

  useEffect(() => {
    if (!focusRunning || focusSeconds === 0) return;
    const timer = window.setInterval(() => setFocusSeconds((current) => Math.max(0, current - 1)), 1000);
    return () => window.clearInterval(timer);
  }, [focusRunning, focusSeconds]);

  const toggleAgent = (id: AgentId) => {
    const isStarting = !active.has(id);
    if (isStarting) setElapsed((current) => ({ ...current, [id]: 0 }));
    setActive((current) => {
      const next = new Set(current);
      if (next.has(id)) {
        next.delete(id);
        const agent = agents.find((item) => item.id === id)!;
        setEvents((items) => [
          { id: Date.now(), icon: '✦', title: `${agent.name} finished`, detail: `Worked for ${formatClock(elapsed[id])}`, time: 'Now' },
          ...items,
        ]);
      } else {
        next.add(id);
      }
      return next;
    });
  };

  const runBuild = () => {
    setBuildProgress(0);
    setBuildState('running');
    setTab('home');
  };

  const startDownload = () => {
    setDownloadBytes(0);
    setDownloadState('running');
    setTab('files');
  };

  const nextTrack = () => {
    setTrackIndex((current) => (current + 1) % tracks.length);
    setMusicPosition(0);
    setMusicPlaying(true);
  };

  const addDroppedFiles = (event: DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    const names = Array.from(event.dataTransfer.files).map((file) => file.name);
    if (names.length) {
      setShelfItems((current) => [...new Set([...names, ...current])]);
      setEvents((current) => [
        { id: Date.now(), icon: '▱', title: `${names.length} ${names.length === 1 ? 'item' : 'items'} added`, detail: 'On the shelf', time: 'Now' },
        ...current,
      ]);
    }
    setIsDropping(false);
  };

  const saveCapture = () => {
    const text = captureDraft.trim();
    if (!text) return;
    setCaptures((current) => [{ id: Date.now(), text, meta: 'Note · just now' }, ...current]);
    setCaptureDraft('');
    setEvents((current) => [{ id: Date.now(), icon: '✎', title: 'Quick Capture saved', detail: text, time: 'Now' }, ...current]);
  };

  const runShortcut = (name: string, destination?: TabId) => {
    setShortcutFeedback(`${name} ran locally`);
    if (destination) setTab(destination);
    window.setTimeout(() => setShortcutFeedback('Ready'), 1800);
  };

  const resetDemo = () => {
    setTab('home');
    setActive(new Set(['claude', 'codex']));
    setElapsed({ claude: 374, codex: 52, gemini: 0, ollama: 0 });
    setBuildState('running');
    setBuildProgress(72);
    setMusicPlaying(true);
    setMusicPosition(78);
    setDownloadState('idle');
    setDownloadBytes(0);
    setFocusSeconds(25 * 60);
    setFocusRunning(false);
    setProfile('Work');
    setPaletteOpen(false);
    setCommandQuery('');
    setUsageRange('1D');
    setBreakdown('Trend');
  };

  const openCommandPalette = () => {
    setCommandQuery('');
    setPaletteOpen(true);
  };

  const metric = (label: string, value: number, tone = 'blue') => (
    <div className="real-metric">
      <span className={`real-ring real-ring--${tone}`} style={{ '--metric': `${value}%` } as CSSProperties}>
        <b>{value}%</b>
      </span>
      <small>{label}</small>
    </div>
  );

  const homeView = (
    <div className="real-home">
      <div className="real-card real-productivity-card">
        <span className="real-focus-ring" style={{ '--metric': `${Math.round((focusSeconds / (25 * 60)) * 100)}%` } as CSSProperties}>◷</span>
        <span><b>{focusRunning ? 'Focus session' : 'Focus timer'}</b><small>{focusRunning ? formatTime(focusSeconds) : '25 minutes'}</small></span>
        <button type="button" onClick={() => setFocusRunning((current) => !current)}>{focusRunning ? 'Ⅱ' : 'Start'}</button>
        {focusRunning && <button type="button" className="is-quiet" onClick={() => { setFocusRunning(false); setFocusSeconds(25 * 60); }}>×</button>}
      </div>

      <div className="real-card real-productivity-card real-meeting-card">
        <span className="real-focus-ring">▣</span>
        <span><b>Product design review</b><small>Starts in 11 minutes</small></span>
        <button type="button">Join</button>
      </div>

      {buildState !== 'idle' && (
        <button type="button" className="real-card real-live-card" onClick={() => setTab('live')}>
          <span className="real-live-icon">↗</span>
          <span><b>Building release</b><small>{buildState === 'done' ? 'Build complete' : `Running tests · ${buildProgress}%`}</small></span>
          <span className="real-meter"><i style={{ width: `${buildProgress}%` }} /></span>
        </button>
      )}

      {active.size > 0 && (
        <div className="real-card real-agent-card">
          {[...active].slice(0, 3).map((id, index) => {
            const agent = agents.find((item) => item.id === id)!;
            return (
              <div className={`real-agent${index > 0 ? ' real-agent--divided' : ''}`} key={id}>
                <AgentOrb id={id} size={26} />
                <span>
                  <span className="real-agent__title">
                    <b>{agent.name}</b>
                    {agent.project && <em>{agent.project}</em>}
                    {agent.model && <strong className="real-model-chip" style={{ '--tint': agent.tint } as CSSProperties}>{agent.model}</strong>}
                  </span>
                  <small>{agent.status}</small>
                </span>
                <time style={{ color: agent.tint }}>{formatClock(elapsed[id])}</time>
              </div>
            );
          })}
          {active.size > 3 && <span className="real-overflow">+{active.size - 3} more working</span>}
        </div>
      )}

      <div className="real-card real-home-media">
        <span className="real-home-art"><Image src={track.artwork} alt="" width={42} height={42} /></span>
        <span><b>{track.title}</b><small>{track.artist} · {track.source}</small></span>
        <div className="real-home-transport"><button type="button" onClick={() => setMusicPosition(0)}>◀</button><button type="button" className="is-main" onClick={() => setMusicPlaying((current) => !current)}>{musicPlaying ? 'Ⅱ' : '▶'}</button><button type="button" onClick={nextTrack}>▶</button></div>
        <span className="real-home-progress"><i style={{ width: `${(musicPosition / track.duration) * 100}%` }} /></span>
      </div>
    </div>
  );

  const summary = usageSummaries[usageRange];
  const spendTotal = summary.claude.cost + summary.codex.cost;
  const tokenTotal = summary.claude.tokens + summary.codex.tokens;
  const rangeScale = tokenTotal / (usageSummaries['1D'].claude.tokens + usageSummaries['1D'].codex.tokens);
  const trendPeak = Math.max(...summary.trend.map((bar) => bar.claude + bar.codex), 1);
  const rangeTitle = usageRange === '1D' ? 'Today' : usageRange === '7D' ? 'Last 7 days' : 'Last 30 days';

  /* As the app does: a working agent's live status goes on its newest session
     if that session wrote to its log in the last 15 minutes, otherwise the
     agent gets a row of its own. Live rows first, then newest. */
  const claimed = new Set<AgentId>();
  const sessionRows: Array<{ id: string; agent: AgentId; project?: string; model?: string; ago?: number; live?: string }> = usageSessions.map((session) => {
    const live = active.has(session.agent) && !claimed.has(session.agent) && session.ago + systemTick < 15 * 60;
    if (live) claimed.add(session.agent);
    return { ...session, ago: session.ago + systemTick, live: live ? agents.find((agent) => agent.id === session.agent)!.status : undefined };
  });
  [...active].filter((id) => !claimed.has(id)).forEach((id) => {
    sessionRows.push({ id: `live:${id}`, agent: id, live: agents.find((agent) => agent.id === id)!.status });
  });
  const visibleSessions = sessionRows
    .sort((a, b) => (a.live ? 0 : 1) - (b.live ? 0 : 1) || (a.ago ?? Infinity) - (b.ago ?? Infinity))
    .slice(0, 3);

  const agentsView = (
    <div className="real-usage">
      <div className="real-usage__row">
        {usageProviders.map((provider) => (
          <div className="real-card real-usage-card" key={provider.id}>
            <div className="real-usage-head">
              <PixelMark id={provider.id} />
              <b>{agents.find((agent) => agent.id === provider.id)!.name}</b>
              <em>{provider.model}</em>
              <strong className="real-plan" style={{ '--tint': tintOf(provider.id) } as CSSProperties}>{provider.plan}</strong>
            </div>
            {provider.limits.map((limit) => {
              const remaining = Math.max(0, limit.resets - systemTick);
              const pace = Math.min(1, Math.max(0, 1 - remaining / limit.window));
              return (
                <div className="real-limit" key={limit.label} aria-label={`${limit.label} limit, ${limit.used} percent used, renews in ${formatCountdown(remaining)}`}>
                  <span className="real-limit__label">
                    <span>{limit.label}</span>
                    <small>↻ {formatCountdown(remaining)}</small>
                    <b>{limit.used}%</b>
                  </span>
                  <span className="real-limit__bar">
                    <i style={{ width: `max(5px, ${limit.used}%)`, background: tintOf(provider.id) }} />
                    <u style={{ left: `calc(${pace * 100}% - .75px)` }} />
                  </span>
                </div>
              );
            })}
            {provider.observedAgo > 15 * 60 && <small className="real-usage-note">Updated {formatAgo(provider.observedAgo + systemTick)}</small>}
          </div>
        ))}
      </div>

      <div className="real-usage__row">
        <div className="real-card real-usage-card">
          <div className="real-usage-head">
            <i className="real-usage-icon">{cardIcons.spending}</i>
            <b>Spending</b>
            <span className="real-chip-picker" role="group" aria-label="Spending range">
              {(['1D', '7D', '30D'] as UsageRange[]).map((range) => <button type="button" aria-pressed={usageRange === range} className={usageRange === range ? 'is-active' : ''} onClick={() => setUsageRange(range)} key={range}>{range}</button>)}
            </span>
          </div>
          <span className="real-spend"><b>{formatUsd(spendTotal)}</b><small>API value</small></span>
          <span className="real-share" aria-hidden="true">
            {providers.map((id) => <i key={id} style={{ flexGrow: summary[id].cost, background: tintOf(id) }} />)}
          </span>
          <span className="real-spend-legend">
            {providers.map((id) => <span key={id}><i style={{ background: tintOf(id) }} />{agents.find((agent) => agent.id === id)!.name}<b>{formatUsd(summary[id].cost)}</b></span>)}
          </span>
          <small className="real-usage-note">{formatTokens(tokenTotal)} tokens · 97% from cache</small>
        </div>

        <div className="real-card real-usage-card">
          <div className="real-usage-head"><i className="real-usage-icon">{cardIcons.sessions}</i><b>Sessions</b></div>
          {visibleSessions.map((row) => (
            <div className="real-session" key={row.id}>
              <span className="real-session__mark">{row.live ? <AgentOrb id={row.agent} size={20} /> : <PixelMark id={row.agent} />}</span>
              <span>
                <b>{row.project ?? agents.find((agent) => agent.id === row.agent)!.name}</b>
                {row.live ? <small style={{ color: tintOf(row.agent) }}>{row.live}</small> : row.model && <small>{row.model}</small>}
              </span>
              <time>{row.live ? (row.model ?? 'Working') : row.ago !== undefined ? formatAgo(row.ago) : '—'}</time>
            </div>
          ))}
        </div>
      </div>

      <div className="real-card real-usage-card">
        <div className="real-usage-head">
          <i className="real-usage-icon">{cardIcons[breakdown]}</i>
          <span className="real-chip-picker real-chip-picker--large" role="group" aria-label="Breakdown">
            {(['Trend', 'Projects', 'Models'] as Breakdown[]).map((item) => <button type="button" aria-pressed={breakdown === item} className={breakdown === item ? 'is-active' : ''} onClick={() => setBreakdown(item)} key={item}>{item}</button>)}
          </span>
          <small className="real-usage-meta">{rangeTitle} · {formatTokens(tokenTotal)} tokens</small>
        </div>
        <div className="real-breakdown-body">
          {breakdown === 'Trend' ? (
            <div className={`real-trend${summary.trend.length > 12 ? ' is-dense' : ''}`} aria-label={`Usage trend, ${rangeTitle}`}>
              <div className="real-trend__bars">
                {summary.trend.map((bar, index) => (
                  <span key={index}>
                    {bar.claude + bar.codex === 0 ? <i className="is-empty" /> : (
                      <>
                        {bar.codex > 0 && <i style={{ height: `max(2px, ${(bar.codex / trendPeak) * 100}%)`, background: tintOf('codex') }} />}
                        {bar.claude > 0 && <i style={{ height: `max(2px, ${(bar.claude / trendPeak) * 100}%)`, background: tintOf('claude') }} />}
                      </>
                    )}
                  </span>
                ))}
              </div>
              <div className="real-trend__labels">{summary.trend.map((bar, index) => <small key={index}>{bar.label}</small>)}</div>
            </div>
          ) : (
            <div className="real-breakdown">
              {usageBreakdowns[breakdown].slice(0, 3).map((row) => (
                <div className="real-breakdown__row" key={row.name}>
                  <i style={{ background: tintOf(row.agent) }} />
                  <b>{row.name}</b>
                  <span className="real-breakdown__bar"><i style={{ width: `${(row.cost / usageBreakdowns[breakdown][0].cost) * 100}%`, background: tintOf(row.agent) }} /></span>
                  <small>{formatTokens(row.tokens * rangeScale)}</small>
                  <strong>{formatUsd(row.cost * rangeScale)}</strong>
                </div>
              ))}
              {usageBreakdowns[breakdown].length > 3 && (() => {
                const rest = usageBreakdowns[breakdown].slice(3);
                const tokens = rest.reduce((sum, row) => sum + row.tokens, 0) * rangeScale;
                const cost = rest.reduce((sum, row) => sum + row.cost, 0) * rangeScale;
                return <small className="real-usage-note">+{rest.length} more · {formatTokens(tokens)} tokens · {formatUsd(cost)}</small>;
              })()}
            </div>
          )}
        </div>
      </div>
    </div>
  );

  const captureView = (
    <div className="real-list-view real-capture-view">
      <form className="real-compose" onSubmit={(event) => { event.preventDefault(); saveCapture(); }}>
        <span>✎</span>
        <input value={captureDraft} onChange={(event) => setCaptureDraft(event.target.value)} placeholder="Capture a note or link…" aria-label="Quick capture text" />
        <button type="button" className="is-quiet" aria-label="Enhance on device">✦</button>
        <button type="button" className="is-quiet" aria-label="Paste clipboard">▣</button>
        <button type="submit" aria-label="Save capture">↑</button>
      </form>
      <div className="real-list-head"><span>{captures.length} captures</span><span><button type="button">Search</button><button type="button" onClick={() => setCaptures([])}>Clear</button></span></div>
      {captures.slice(0, 3).map((capture, index) => <div className="real-capture-row" key={capture.id}><button type="button" className="real-row-main"><i>{capture.text.startsWith('http') ? '↗' : '▤'}</i><span><b>{capture.text}</b><small>{capture.meta}</small></span></button><button type="button" className={index === 0 ? 'is-pinned' : ''} aria-label="Pin capture">⌖</button><button type="button" aria-label="Remove capture">×</button></div>)}
      {captures.length === 0 && <button type="button" className="real-empty" onClick={() => setCaptureDraft('A new capture')}><b>✎</b><span>Capture something<small>Type a note or paste selected text.</small></span></button>}
    </div>
  );

  const shortcutsView = (
    <div className="real-list-view real-shortcuts-view">
      <div className="real-shortcut-grid">
        <button type="button" onClick={() => runShortcut('Calculator')}><i>▦</i><span><b>Calculator</b><small>Open app</small></span></button>
        <button type="button" onClick={() => runShortcut('Start my day')}><i>⌘</i><span><b>Start my day</b><small>Run Shortcut</small></span></button>
        <button type="button" onClick={() => runShortcut('System', 'system')}><i>◴</i><span><b>System</b><small>Toggle widget</small></span></button>
        <button type="button" onClick={() => runShortcut('Clipboard', 'clipboard')}><i>▤</i><span><b>Clipboard</b><small>Toggle widget</small></span></button>
        <button type="button" onClick={() => runShortcut('Music', 'music')}><i>♪</i><span><b>Music</b><small>Toggle widget</small></span></button>
        <button type="button" onClick={() => runShortcut('Capture', 'capture')}><i>✎</i><span><b>Capture</b><small>Toggle widget</small></span></button>
      </div>
      <small className="real-shortcut-feedback">{shortcutFeedback}</small>
    </div>
  );

  const musicView = (
    <div className="real-player">
      <span className="real-art real-art--spotify"><Image src={track.artwork} alt={`${track.album} album cover`} width={82} height={82} /></span>
      <div className="real-player__body">
        <span><b>{track.title}</b><small>{track.artist} — {track.album}</small><em>{track.source}</em></span>
        <input aria-label="Track position" type="range" min="0" max={track.duration} value={musicPosition} onChange={(event) => setMusicPosition(Number(event.target.value))} />
        <span className="real-times"><small>{formatTime(musicPosition)}</small><small>{formatTime(track.duration)}</small></span>
        <div className="real-transport">
          <button type="button" onClick={() => setMusicPosition(0)} aria-label="Previous track">◀◀</button>
          <button className="is-main" type="button" onClick={() => setMusicPlaying((current) => !current)} aria-label={musicPlaying ? 'Pause' : 'Play'}>{musicPlaying ? 'Ⅱ' : '▶'}</button>
          <button type="button" onClick={nextTrack} aria-label="Next track">▶▶</button>
          <span className={musicPlaying ? 'is-playing' : ''}><i /><i /><i /><i /></span>
        </div>
      </div>
    </div>
  );

  const filesView = (
    <div className="real-list-view">
      <div className="real-list-head"><span>Recent transfers</span><button type="button" onClick={startDownload}>{downloadState === 'running' ? 'Restart' : 'Simulate download'}</button></div>
      {downloadState === 'idle' ? (
        <button type="button" className="real-empty" onClick={startDownload}><b>↓</b><span>No recent transfers<small>Click to simulate a download.</small></span></button>
      ) : (
        <div className="real-file-row">
          <span className="file-icon">XIP</span>
          <span><b>Xcode_26.xip</b><small>{(downloadBytes / 1024).toFixed(1)} GB{downloadState === 'running' ? ' · 22.4 MB/s' : ''}</small></span>
          {downloadState === 'running' ? <i className="spinner" /> : <button type="button" aria-label="Reveal in Finder">⌕</button>}
        </div>
      )}
      <div className="real-file-row">
        <span className="file-icon file-icon--soft">FIG</span>
        <span><b>design-review.sketch</b><small>184 MB</small></span>
        <button type="button" aria-label="Reveal in Finder">⌕</button>
      </div>
    </div>
  );

  const liveView = (
    <div className="real-list-view">
      <div className="real-list-head"><span>Live activities</span><button type="button" onClick={runBuild}>Run build</button></div>
      {buildState === 'idle' ? (
        <button type="button" className="real-empty" onClick={runBuild}><b>⌁</b><span>No live activities<small>Click to start one from a script.</small></span></button>
      ) : (
        <button type="button" className="real-live-row" onClick={runBuild}>
          <span className="real-progress-ring" style={{ '--metric': `${buildProgress}%` } as CSSProperties}><i>↗</i></span>
          <span><b>Building release</b><small>{buildState === 'done' ? 'Build succeeded · click to run again' : 'Running tests'}</small></span>
          <strong>{buildProgress}%</strong>
        </button>
      )}
    </div>
  );

  const activityView = (
    <div className="real-list-view">
      <div className="real-list-head"><span>Recent</span><button type="button" onClick={() => setEvents([])}>Clear</button></div>
      {events.length === 0 ? <div className="real-empty"><b>○</b><span>Nothing yet<small>Your demo actions land here.</small></span></div> : events.slice(0, 4).map((event) => (
        <div className="real-event" key={event.id}><i>{event.icon}</i><span><b>{event.title}</b><small>{event.detail}</small></span><time>{event.time}</time></div>
      ))}
    </div>
  );

  const shelfView = (
    <div className="real-list-view">
      <div className="real-list-head"><span>{shelfItems.length} items</span><button type="button" onClick={() => setShelfItems([])}>Clear</button></div>
      <div className={`real-shelf${isDropping ? ' is-dropping' : ''}`} onDragOver={(event) => { event.preventDefault(); setIsDropping(true); }} onDragLeave={() => setIsDropping(false)} onDrop={addDroppedFiles}>
        {shelfItems.map((item) => <button type="button" key={item} onClick={() => setShelfItems((current) => current.filter((name) => name !== item))}><span>{item.split('.').pop()?.slice(0, 3).toUpperCase()}</span><small>{item}</small><i>×</i></button>)}
        <div className="real-shelf__drop"><b>＋</b><small>Drop files here</small></div>
      </div>
    </div>
  );

  const visibleClipboard = clipboardItems.filter((item) => item.text.toLowerCase().includes(clipboardSearch.toLowerCase()));
  const clipboardView = (
    <div className="real-list-view real-clipboard-view">
      <div className="real-clipboard-controls"><span>⌕</span><input className="real-search" value={clipboardSearch} onChange={(event) => setClipboardSearch(event.target.value)} placeholder="Search clipboard" aria-label="Search clipboard history" /><button type="button" onClick={() => setClipboardPaused((current) => !current)}>{clipboardPaused ? '▶' : 'Ⅱ'}</button><button type="button">♲</button></div>
      {clipboardPaused && <div className="real-privacy-note">Paused · concealed and transient content is always ignored</div>}
      {visibleClipboard.map((item, index) => <div className="real-capture-row" key={item.id}><button type="button" className="real-row-main"><i>{item.meta.startsWith('Link') ? '↗' : item.meta.startsWith('Image') ? '▧' : '☰'}</i><span><b>{item.text}</b><small>{item.meta}</small></span></button><button type="button" className={index === 0 ? 'is-pinned' : ''} aria-label="Pin clipboard item">⌖</button><button type="button" aria-label="Remove clipboard item">×</button></div>)}
    </div>
  );

  const systemView = (
    <div className="real-system-wrap">
      <div className="real-system">{metric('CPU', cpu)}{metric('Memory', memory, 'warm')}{metric('Battery', 100, 'green')}<div className="real-metric real-network"><b><i>↓</i> {down}</b><b><i>↑</i> 118 KB/s</b><small>Network</small></div></div>
      <div className="real-device-panel"><div><span>▱ &nbsp; Device batteries</span><small>4 devices</small></div><div><span><i>▰</i><b>This Mac<small>100%</small></b></span><span><i>⌨</i><b>Magic Keyboard<small>82%</small></b></span><span className="is-low"><i>◉</i><b>Magic Mouse<small>17%</small></b></span><span className="is-good"><i>ϟ</i><b>Headphones<small>63%</small></b></span></div></div>
    </div>
  );

  const views: Record<TabId, React.ReactNode> = {
    home: homeView,
    agents: agentsView,
    capture: captureView,
    shortcuts: shortcutsView,
    music: musicView,
    system: systemView,
    live: liveView,
    files: filesView,
    activity: activityView,
    clipboard: clipboardView,
    shelf: shelfView,
  };

  const paletteCommands = [
    { id: 'capture', icon: '✎', title: 'Create quick capture', detail: 'Save a note or link', kind: 'Action', run: () => { setTab('capture'); setPaletteOpen(false); } },
    { id: 'focus', icon: '◷', title: 'Start focus timer', detail: 'Focus for 25 minutes', kind: 'Action', run: () => { setFocusRunning(true); setTab('home'); setPaletteOpen(false); } },
    { id: 'calculator', icon: '▦', title: 'Calculator', detail: 'Open app', kind: 'Shortcut', run: () => { runShortcut('Calculator'); setPaletteOpen(false); } },
    { id: 'start-day', icon: '⌘', title: 'Start my day', detail: 'Run Shortcut', kind: 'Shortcut', run: () => { runShortcut('Start my day'); setPaletteOpen(false); } },
    { id: 'system', icon: '◴', title: 'System', detail: 'Toggle widget', kind: 'Shortcut', run: () => { setTab('system'); setPaletteOpen(false); } },
    { id: 'clipboard', icon: '▤', title: 'Clipboard', detail: 'Toggle widget', kind: 'Shortcut', run: () => { setTab('clipboard'); setPaletteOpen(false); } },
    { id: 'agents', icon: '⌬', title: 'Agent usage', detail: 'Plan limits and spend', kind: 'Widget', run: () => { setTab('agents'); setPaletteOpen(false); } },
  ];
  const visiblePaletteCommands = paletteCommands.filter((command) => `${command.title} ${command.detail}`.toLowerCase().includes(commandQuery.trim().toLowerCase()));

  const commandSurface = (
    <div className="real-command-surface real-command-surface--embedded" role="dialog" aria-label="Bondex command palette">
      <div className="real-command-search-row">
        <span aria-hidden="true">⌕</span>
        <input
          autoFocus
          value={commandQuery}
          onChange={(event) => setCommandQuery(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Escape') setPaletteOpen(false);
            if (event.key === 'Enter') visiblePaletteCommands[0]?.run();
          }}
          placeholder="Search commands, captures, files…"
          aria-label="Search commands"
        />
        <kbd>⌥ P</kbd>
        <button type="button" onClick={() => setPaletteOpen(false)} aria-label="Close command palette">×</button>
      </div>
      <div className="real-command-results" role="listbox" aria-label="Commands">
        {visiblePaletteCommands.map((command, index) => (
          <button type="button" role="option" aria-selected={index === 0} className={index === 0 ? 'is-selected' : ''} onClick={command.run} key={command.id}>
            <i>{command.icon}</i>
            <span><b>{command.title}</b><small>{command.detail}</small></span>
            <em>{command.kind}</em>
            {index === 0 && <kbd>↵</kbd>}
          </button>
        ))}
        {visiblePaletteCommands.length === 0 && <div className="real-command-empty"><b>No matching commands</b><small>Try “focus”, “capture”, or “clipboard”.</small></div>}
      </div>
      <div className="real-command-footer"><span>↑↓ &nbsp; Navigate</span><span>↵ &nbsp; Run</span><button type="button" onClick={() => setPaletteOpen(false)}>Close</button></div>
    </div>
  );

  return (
    <div className="product-shot product-shot--agents real-product" style={{ '--demo-accent': accentColors[accent] } as CSSProperties} aria-label="Interactive Bondex Notch product demo">
      <div className="real-demo-top">
        <span className="real-demo-top__status"><i /><span><b>Interactive app preview</b><small>Explore the real app flow</small></span></span>
        <button type="button" onClick={resetDemo}>↺ Reset</button>
      </div>
      <div className="real-panel-frame" data-tab={tab}>
        <div className="real-panel">
          <span className="real-panel__camera" aria-hidden="true" />
          <div className="real-panel__content">
            <div className="real-header">
              <div className="real-tabs" role="tablist" aria-label="Bondex widgets">
                {tabs.map((item) => <button type="button" role="tab" aria-label={item.label} aria-selected={tab === item.id} className={tab === item.id ? 'is-active' : ''} onClick={() => setTab(item.id)} key={item.id}><i>{item.icon}</i>{tab === item.id && <span>{item.label}</span>}</button>)}
              </div>
              <button type="button" className="real-profile" aria-label={`${profile} profile`} onClick={() => setProfile((current) => current === 'Work' ? 'Meeting' : 'Work')}>◉</button>
              <span className="real-privacy" aria-label="Microphone in use">●</span>
              <button type="button" className="real-palette-trigger" aria-label="Open command palette" onClick={openCommandPalette}>⌕</button>
              <button type="button" className="real-close" aria-label="Collapse panel">×</button>
            </div>
            <div className="real-divider" />
            <div className="real-view" key={tab}>{views[tab]}</div>
          </div>
          {paletteOpen && <div className="real-command-panel-overlay">{commandSurface}</div>}
        </div>
      </div>

      <div className="real-controls" aria-label="Demo controls">
        <div className="real-control-block real-control-block--agents">
          <span className="real-control-label">Agent signals</span>
          <div className="real-agent-toggles">{agents.map((agent) => <button type="button" aria-pressed={active.has(agent.id)} className={active.has(agent.id) ? 'is-active' : ''} onClick={() => toggleAgent(agent.id)} key={agent.id}>{agent.name}</button>)}</div>
        </div>
        <div className="real-control-block real-control-block--actions">
          <span className="real-control-label">Try an action</span>
          <div><button type="button" onClick={runBuild}>Run build</button><button type="button" onClick={startDownload}>Download</button><button type="button" onClick={() => setTab('agents')}>Agent usage</button><button type="button" onClick={openCommandPalette}>Commands</button></div>
        </div>
        <div className="real-control-block real-control-block--accent">
          <span className="real-control-label">Accent</span>
          <span className="real-swatches" aria-label="Accent color">{(['ocean', 'violet', 'forest'] as Accent[]).map((color) => <button type="button" className={accent === color ? 'is-active' : ''} style={{ '--swatch': accentColors[color] } as CSSProperties} onClick={() => setAccent(color)} aria-label={`${color} accent`} key={color} />)}</span>
        </div>
      </div>
      <p className="real-demo-note">Eleven live tabs · sample usage figures · drop files onto Shelf</p>
    </div>
  );
}
