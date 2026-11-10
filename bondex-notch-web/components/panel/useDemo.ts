'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  type AccentId, type AgentId, type Command, type CustomAction, type ProfileId, type TabId, type UsageRange,
  BUDDY_GOALS, BUDDY_WATER_CREDIT, CUSTOM_ACTIONS, PROFILES, SETTINGS_PAGES, TAB_ORDER, TABS,
  accentHex, actionSubtitle, actionSymbol, agentName, buddyEnergy, clockString, searchCommands,
} from './model';

/* The app's state, small enough for a page: what is working, playing,
   downloading and saved, and the handful of rules that decide what the panel
   and the peek show. Both demos run on it, so they can only disagree about
   what they start with. */

export type EventKind = 'music' | 'download' | 'system' | 'shelf' | 'agent' | 'live' | 'app';

/** `NotchEvent.Kind`: symbol, tint, and whether it earns a banner. */
export const EVENT_KINDS: Record<EventKind, { symbol: string; tint: string; banner: boolean }> = {
  music: { symbol: 'music.note', tint: '#fa5473', banner: false },
  download: { symbol: 'arrow.down.circle.fill', tint: '#4a9efa', banner: true },
  system: { symbol: 'cpu', tint: '#fcb840', banner: true },
  shelf: { symbol: 'tray.full.fill', tint: '#52cc8c', banner: true },
  agent: { symbol: 'sparkle', tint: '#d9784a', banner: false },
  live: { symbol: 'waveform.path.ecg', tint: '#9e7afa', banner: true },
  app: { symbol: 'bell.fill', tint: '#bfbfbf', banner: true },
};

export interface NotchEvent {
  id: number;
  kind: EventKind;
  title: string;
  subtitle?: string;
  /** Seconds before the page loaded, or the tick it happened on. */
  at: { ago: number } | { tick: number };
  agent?: AgentId;
}

export interface WorkingAgent {
  id: AgentId;
  /** The tick the run started on; negative for runs already under way. */
  since: number;
  attention: boolean;
}

export type FileIcon = 'png' | 'xip' | 'dmg' | 'zip' | 'txt' | 'mov';

export interface DemoSeed {
  agents: AgentId[];
  build: boolean;
  meeting: boolean;
}

export const TRACKS = [
  { title: 'Blinding Lights', artist: 'The Weeknd', album: 'After Hours', duration: 200, artwork: '/album-art/after-hours.jpg' },
  { title: 'Die With A Smile', artist: 'Lady Gaga & Bruno Mars', album: 'Die With A Smile', duration: 251, artwork: '/album-art/die-with-a-smile.jpg' },
];

/** Elapsed seconds the renderer gives each agent's run. */
const RUN_SO_FAR: Record<AgentId, number> = { claude: 374, codex: 52, gemini: 3725, ollama: 20 };

const ATTENTION_STATUS = 'Approve: Running swift test';
const FOCUS_MINUTES = 25;
const MEETING_IN = 7 * 60;

/** `ByteCountFormatter`, file style: "184 MB", "7.4 GB", "12 KB". */
export function byteString(bytes: number) {
  const trim = (value: string) => value.replace(/\.?0+$/, '');
  if (bytes >= 1e9) return `${trim((bytes / 1e9).toFixed(2))} GB`;
  if (bytes >= 1e6) return `${trim((bytes / 1e6).toFixed(1))} MB`;
  return `${Math.max(Math.round(bytes / 1e3), 0)} KB`;
}

let nextId = 1000;
const id = () => (nextId += 1);

export function useDemo(seed: DemoSeed) {
  /* ── Clock ── */
  // `tick` counts seconds since the page loaded, and only while the demo is
  // on screen: a once-a-second render landing mid-animation elsewhere on the
  // page costs that animation a frame. `loadedAt` is set after hydration so
  // the server and the browser render the same text.
  const [tick, setTick] = useState(0);
  const [loadedAt, setLoadedAt] = useState<Date | null>(null);
  const [onScreen, setOnScreen] = useState(false);
  // A callback ref, so the hook's result holds no ref object.
  const [root, setRoot] = useState<HTMLElement | null>(null);

  /* ── Panel ── */
  const [tab, setTabState] = useState<TabId>('home');
  const [tabAdvances, setTabAdvances] = useState(true);
  const [disabledTabs, setDisabledTabs] = useState<Set<TabId>>(() => new Set());
  const [accent, setAccent] = useState<AccentId>('graphite');
  const [profileMode, setProfileMode] = useState<'off' | 'manual' | 'automatic'>('off');
  const [profile, setProfile] = useState<ProfileId | null>(null);

  /* ── Live state ── */
  const [agents, setAgents] = useState<WorkingAgent[]>(() =>
    seed.agents.map((agent) => ({ id: agent, since: -RUN_SO_FAR[agent], attention: false })),
  );
  const [build, setBuild] = useState<{ progress: number } | null>(() => (seed.build ? { progress: 0.72 } : null));
  const [meeting, setMeeting] = useState(seed.meeting);
  const [focus, setFocus] = useState<{ remaining: number; running: boolean } | null>(null);
  const [music, setMusic] = useState({ playing: true, position: 78, track: 0 });
  const [banner, setBanner] = useState<NotchEvent | null>(null);

  const [events, setEvents] = useState<NotchEvent[]>(() => [
    { id: 1, kind: 'download', title: 'Xcode_26.xip', subtitle: 'Download complete · 7.4 GB', at: { ago: 3 * 60 } },
    { id: 2, kind: 'music', title: 'Blinding Lights', subtitle: 'The Weeknd', at: { ago: 6 * 60 } },
    { id: 3, kind: 'agent', agent: 'codex', title: 'Codex finished', subtitle: 'Worked for 4:12', at: { ago: 14 * 60 } },
  ]);
  const [files, setFiles] = useState<Array<{ id: number; name: string; icon: FileIcon; bytes: number; rate: number; complete: boolean }>>(() => [
    { id: 1, name: 'Xcode_26.xip', icon: 'xip', bytes: 7.4e9, rate: 0, complete: true },
  ]);

  const [captures, setCaptures] = useState(() => [
    { id: 1, text: 'Review the release checklist before 4 PM', ago: 20 * 60, pinned: true },
    { id: 2, text: 'https://developer.apple.com/design/human-interface-guidelines/', ago: 45 * 60, pinned: false },
  ]);
  const [draft, setDraft] = useState('');
  const [clipboard, setClipboard] = useState(() => [
    { id: 1, kind: 'link' as const, text: 'https://developer.apple.com/documentation/vision', pinned: true },
    { id: 2, kind: 'text' as const, text: 'Ship the compact clipboard history this week', pinned: false },
    { id: 3, kind: 'image' as const, text: 'Image', bytes: 1.2e6, pinned: false },
  ]);
  const [clipboardPaused, setClipboardPaused] = useState(false);
  const [shelf, setShelf] = useState<Array<{ id: number; name: string; icon: FileIcon }>>(() => [
    { id: 1, name: 'Hero artwork.png', icon: 'png' },
    { id: 2, name: 'Launch notes.txt', icon: 'txt' },
    { id: 3, name: 'Demo reel.mov', icon: 'mov' },
  ]);
  const [feedback, setFeedback] = useState<{ message: string; error: boolean } | null>(null);

  /* ── Wellness buddy · WellnessBuddyService ── */
  // The stretch is in minutes and stands still unless something moves it:
  // the page has no idle time to read, and a buddy wilting on its own would
  // take over the hero's peek. "Work an hour" plays an hour forward so the
  // plant can be watched wilting.
  const [buddy, setBuddy] = useState({ stretch: 22, glasses: 5, breaks: 3, lastWaterAgo: 25, snoozed: false, waterTick: 0 });
  const [fastForward, setFastForward] = useState(0);

  /* ── Palette ── */
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [query, setQueryState] = useState('');
  const [selected, setSelected] = useState(0);

  /* ── Agents tab ── */
  const [usageRange, setUsageRange] = useState<UsageRange>('today');

  useEffect(() => {
    const frame = requestAnimationFrame(() => setLoadedAt(new Date()));
    return () => cancelAnimationFrame(frame);
  }, []);

  useEffect(() => {
    if (!root) return;
    const observer = new IntersectionObserver(([entry]) => setOnScreen(entry.isIntersecting));
    observer.observe(root);
    return () => observer.disconnect();
  }, [root]);

  /* ── Events ── */

  const post = useCallback((event: Omit<NotchEvent, 'id' | 'at'>) => {
    const posted = { ...event, id: id(), at: { tick } } as NotchEvent;
    setEvents((current) => [posted, ...current].slice(0, 40));
    if (EVENT_KINDS[event.kind].banner) setBanner(posted);
  }, [tick]);

  // A banner stands for 3.2 seconds, then the peek returns to what it was.
  useEffect(() => {
    if (!banner) return;
    const timer = setTimeout(() => setBanner(null), 3200);
    return () => clearTimeout(timer);
  }, [banner]);

  /* ── Per-second state ── */

  const focusRef = useRef(focus);
  useEffect(() => {
    focusRef.current = focus;
  }, [focus]);

  useEffect(() => {
    if (!onScreen) return;
    const timer = window.setInterval(() => {
      setTick((current) => current + 1);
      setMusic((current) => {
        if (!current.playing) return current;
        const track = TRACKS[current.track];
        if (current.position + 1 < track.duration) return { ...current, position: current.position + 1 };
        return { ...current, track: (current.track + 1) % TRACKS.length, position: 0 };
      });
      const running = focusRef.current;
      if (running?.running) {
        if (running.remaining > 1) {
          setFocus({ ...running, remaining: running.remaining - 1 });
        } else {
          setFocus(null);
          post({ kind: 'app', title: 'Focus complete', subtitle: 'Time for a break' });
        }
      }
    }, 1000);
    return () => window.clearInterval(timer);
  }, [onScreen, post]);

  // A new track is announced to the feed, never as a banner.
  const announcedTrack = useRef(music.track);
  useEffect(() => {
    if (announcedTrack.current === music.track) return;
    announcedTrack.current = music.track;
    const track = TRACKS[music.track];
    post({ kind: 'music', title: track.title, subtitle: track.artist });
  }, [music.track, post]);

  /* ── Live activity: a build reporting progress from a script ── */

  const buildRunning = build !== null && build.progress < 1;
  const buildRef = useRef(build);
  useEffect(() => {
    buildRef.current = build;
  }, [build]);

  useEffect(() => {
    if (!buildRunning) return;
    const timer = window.setInterval(() => {
      const current = buildRef.current;
      if (!current) return;
      const progress = Math.min(current.progress + 0.01, 1);
      if (progress < 1) {
        setBuild({ progress });
        return;
      }
      // A finished activity leaves the peek and the Live tab, and lands in
      // the feed: `activity.completionMessage ?? activity.subtitle`.
      setBuild(null);
      post({ kind: 'live', title: 'Building release finished', subtitle: 'Build succeeded' });
    }, 400);
    return () => window.clearInterval(timer);
  }, [buildRunning, post]);

  const runBuild = useCallback(() => setBuild({ progress: 0 }), []);

  /* ── Wellness buddy ── */

  useEffect(() => {
    if (fastForward <= 0) return;
    const timer = window.setTimeout(() => {
      const step = Math.min(fastForward, 2);
      setBuddy((current) => ({ ...current, stretch: current.stretch + step, lastWaterAgo: current.lastWaterAgo + step }));
      setFastForward((current) => current - step);
    }, 50);
    return () => window.clearTimeout(timer);
  }, [fastForward]);

  const workAnHour = useCallback(() => {
    setBuddy((current) => ({ ...current, snoozed: false }));
    setFastForward(60);
    // An hour on, the meeting that was seven minutes away is over.
    setMeeting(false);
  }, []);
  const logWater = useCallback(() => {
    setBuddy((current) => ({
      ...current,
      glasses: Math.min(current.glasses + 1, 40),
      stretch: Math.max(current.stretch - BUDDY_WATER_CREDIT, 0),
      lastWaterAgo: 0,
      waterTick: current.waterTick + 1,
    }));
  }, []);
  const removeWater = useCallback(() => setBuddy((current) => ({ ...current, glasses: Math.max(current.glasses - 1, 0) })), []);
  const takeBreak = useCallback(() => {
    setFastForward(0);
    setBuddy((current) => ({ ...current, breaks: current.breaks + 1, stretch: 0, snoozed: false }));
  }, []);
  const snoozeBuddy = useCallback(() => setBuddy((current) => ({ ...current, snoozed: true })), []);

  const buddyNeedsBreak = buddy.stretch >= BUDDY_GOALS.breakMinutes && !buddy.snoozed;

  /* ── Downloads ── */

  const downloading = files.some((file) => !file.complete);
  useEffect(() => {
    if (!downloading) return;
    const total = 2.4e9;
    const timer = window.setInterval(() => {
      setFiles((current) => current.map((file) => {
        if (file.complete) return file;
        const bytes = Math.min(file.bytes + 3.9e7, total);
        return { ...file, bytes, rate: 3.9e8, complete: bytes >= total };
      }));
    }, 100);
    return () => window.clearInterval(timer);
  }, [downloading]);

  const finished = useRef(new Set<number>());
  useEffect(() => {
    files.forEach((file) => {
      if (!file.complete || file.id < 1000 || finished.current.has(file.id)) return;
      finished.current.add(file.id);
      post({ kind: 'download', title: file.name, subtitle: `Download complete · ${byteString(file.bytes)}` });
    });
  }, [files, post]);

  const startDownload = useCallback(() => {
    setFiles((current) => [
      { id: id(), name: 'Sample footage.mov', icon: 'mov', bytes: 0, rate: 0, complete: false },
      ...current.filter((file) => file.complete),
    ]);
  }, []);

  /* ── Agents ── */

  const toggleAgent = useCallback((agent: AgentId) => {
    const running = agents.find((item) => item.id === agent);
    if (!running) {
      setAgents([{ id: agent, since: tick, attention: false }, ...agents]);
      return;
    }
    setAgents(agents.filter((item) => item.id !== agent));
    post({ kind: 'agent', agent, title: `${agentName(agent)} finished`, subtitle: `Worked for ${clockString(tick - running.since)}` });
  }, [agents, post, tick]);

  /** Stops the first working agent at a prompt, or answers it. */
  const toggleAttention = useCallback(() => {
    setAgents((current) => {
      if (current.length === 0) return [{ id: 'claude', since: tick, attention: true }];
      const waiting = current.some((agent) => agent.attention);
      // A waiting agent leads, as AgentActivityService sorts it.
      if (waiting) return current.map((agent) => ({ ...agent, attention: false }));
      const [first, ...rest] = current;
      return [{ ...first, attention: true }, ...rest];
    });
  }, [tick]);

  const agentStatus = (agent: WorkingAgent) =>
    agent.attention ? ATTENTION_STATUS : (AGENT_STATUS[agent.id] ?? 'Working');

  /* ── Focus · FocusTimerService ── */

  const startFocus = useCallback(() => setFocus({ remaining: FOCUS_MINUTES * 60, running: true }), []);
  const toggleFocusRunning = useCallback(() => setFocus((current) => (current ? { ...current, running: !current.running } : current)), []);
  const cancelFocus = useCallback(() => setFocus(null), []);

  /* ── Music ── */

  const playPause = useCallback(() => setMusic((current) => ({ ...current, playing: !current.playing })), []);
  const nextTrack = useCallback(() => setMusic((current) => ({ playing: true, position: 0, track: (current.track + 1) % TRACKS.length })), []);
  const previousTrack = useCallback(() => setMusic((current) => ({ ...current, position: 0 })), []);

  /* ── Tabs and profiles ── */

  const activeProfile = profile ? PROFILES.find((item) => item.id === profile) ?? null : null;
  const effectiveAccent = activeProfile?.accent ?? accent;

  /** `AppEnvironment.availableTabs`: Home always, then what is enabled, in order. */
  const tabs = useMemo(() => {
    const order = activeProfile ? activeProfile.order : TAB_ORDER;
    return order.filter((item) => item === 'home' || !disabledTabs.has(item));
  }, [activeProfile, disabledTabs]);
  const isEnabled = useCallback((item: TabId) => tabs.includes(item), [tabs]);

  const setTab = useCallback((next: TabId) => {
    setTabAdvances(tabs.indexOf(next) >= tabs.indexOf(tab));
    setTabState(next);
  }, [tab, tabs]);

  // A tab switched off while showing falls back to Home.
  const shownTab: TabId = tabs.includes(tab) ? tab : 'home';

  /** `AppEnvironment.toggleWidget`: nil for Home, which is always shown, and
      for the Shortcuts grid, which is a setting of its own. */
  const toggleWidget = useCallback((item: TabId): boolean | null => {
    if (item === 'home' || item === 'shortcuts') return null;
    const enable = !tabs.includes(item);
    setDisabledTabs((current) => {
      const next = new Set(current);
      if (enable) next.delete(item);
      else next.add(item);
      return next;
    });
    return enable;
  }, [tabs]);

  useEffect(() => {
    if (!feedback) return;
    const timer = setTimeout(() => setFeedback(null), 2200);
    return () => clearTimeout(timer);
  }, [feedback]);

  /** `CustomActionService.perform`. */
  const perform = useCallback((action: CustomAction) => {
    let result: { message: string; error: boolean };
    if (action.kind === 'app') result = { message: `Opened ${action.title}`, error: false };
    else if (action.kind === 'shortcut') result = { message: `Running ${action.title}`, error: false };
    else {
      const enabled = toggleWidget(action.tab);
      result = enabled === null
        ? { message: `${TABS[action.tab].title} can’t be toggled`, error: true }
        : { message: `${TABS[action.tab].title} ${enabled ? 'enabled' : 'disabled'}`, error: false };
    }
    setFeedback(result);
  }, [toggleWidget]);

  /* ── Captures, clipboard, shelf ── */

  const saveDraft = useCallback(() => {
    const text = draft.trim();
    if (!text) return;
    setCaptures((current) => [{ id: id(), text, ago: -tick, pinned: false }, ...current]);
    setDraft('');
  }, [draft, tick]);

  const pasteIntoDraft = useCallback(() => {
    const first = clipboard.find((item) => item.kind !== 'image');
    if (first) setDraft(first.text);
  }, [clipboard]);

  const addToShelf = useCallback((names: string[]) => {
    if (names.length === 0) return;
    const icon = (name: string): FileIcon => {
      const ext = name.split('.').pop()?.toLowerCase() ?? '';
      if (['png', 'jpg', 'jpeg', 'gif', 'heic', 'webp'].includes(ext)) return 'png';
      if (['mov', 'mp4', 'm4v'].includes(ext)) return 'mov';
      if (ext === 'zip') return 'zip';
      if (ext === 'dmg') return 'dmg';
      return 'txt';
    };
    setShelf((current) => [
      ...names.map((name) => ({ id: id(), name, icon: icon(name) })),
      ...current.filter((item) => !names.includes(item.name)),
    ]);
    post({ kind: 'shelf', title: names.length === 1 ? names[0] : `${names.length} items added`, subtitle: 'On the shelf' });
  }, [post]);

  /* ── Command palette · AppEnvironment.commandPaletteCommands ── */

  type Run = () => void;
  const commandList = useMemo(() => {
    const list: Array<Command & { run: Run }> = [];
    const add = (command: Command, run: Run) => list.push({ ...command, run });

    if (isEnabled('capture')) {
      add({ id: 'capture-new', title: 'Create quick capture', subtitle: 'Save a note or link', symbol: 'square.and.pencil', category: 'Action', keywords: ['new', 'note', 'write', 'save'], priority: 0 },
        () => setTab('capture'));
    }

    const focusCommand = focus
      ? { title: focus.running ? 'Pause focus timer' : 'Resume focus timer', subtitle: `${clockString(focus.remaining)} remaining` }
      : { title: 'Start focus timer', subtitle: `Focus for ${FOCUS_MINUTES} minutes` };
    add({ id: 'focus-toggle', ...focusCommand, symbol: 'timer', category: 'Action', keywords: ['pomodoro', 'work', 'pause', 'resume'], priority: 1 },
      () => (focus ? toggleFocusRunning() : startFocus()));

    if (isEnabled('buddy')) {
      add({ id: 'buddy-water', title: 'Log a glass of water', subtitle: `${buddy.glasses} of ${BUDDY_GOALS.water} today`, symbol: 'drop.fill', category: 'Action', keywords: ['drink', 'hydrate', 'buddy', 'wellness', 'glass'], priority: 2 },
        logWater);
      add({ id: 'buddy-break', title: 'Log a stretch break', subtitle: `${buddy.breaks} of ${BUDDY_GOALS.breaks} breaks today`, symbol: 'figure.walk', category: 'Action', keywords: ['stretch', 'move', 'rest', 'buddy', 'wellness'], priority: 3 },
        takeBreak);
    }

    if (isEnabled('shortcuts')) {
      CUSTOM_ACTIONS.forEach((action, index) => add(
        { id: `action-${action.id}`, title: action.title, subtitle: actionSubtitle(action), symbol: actionSymbol(action), category: 'Shortcut', keywords: ['app', 'shortcut', 'run', 'open', 'toggle'], priority: 10 + index },
        () => perform(action),
      ));
    }

    tabs.forEach((item, index) => add(
      { id: `widget-${item}`, title: `Show ${TABS[item].title}`, subtitle: `Switch to the ${TABS[item].title} widget`, symbol: TABS[item].symbol, category: 'Widget', keywords: [item, 'tab', 'open', 'switch'], priority: 30 + index },
      () => setTab(item),
    ));

    if (isEnabled('clipboard')) {
      clipboard.forEach((item, index) => add(
        { id: `clipboard-${item.id}`, title: item.kind === 'image' ? 'Image' : item.text, subtitle: `Copy from Clipboard · ${clipboardDetail(item)}`, symbol: clipboardSymbol(item.kind), category: 'Clipboard', keywords: ['paste', 'copy', 'history'], priority: 50 + index },
        () => undefined,
      ));
    }
    if (isEnabled('capture')) {
      captures.forEach((item, index) => add(
        { id: `capture-${item.id}`, title: item.text, subtitle: `Copy from Quick Capture · ${captureDetail(item, loadedAt)}`, symbol: isLink(item.text) ? 'link' : 'note.text', category: 'Capture', keywords: ['note', 'saved', 'copy'], priority: 60 + index },
        () => undefined,
      ));
    }
    if (isEnabled('shelf')) {
      shelf.forEach((item, index) => add(
        { id: `shelf-${item.id}`, title: item.name, subtitle: 'Reveal shelf item in Finder', symbol: 'doc.fill', category: 'Shelf', keywords: ['file', 'finder', 'reveal'], priority: 70 + index },
        () => undefined,
      ));
    }

    if (profileMode !== 'automatic') {
      add({ id: 'profiles-automatic', title: 'Use Automatic Profiles', subtitle: 'Switch profiles when your context changes', symbol: 'wand.and.stars', category: 'Profile', keywords: ['smart', 'context', 'mode'], priority: 80 },
        () => { setProfileMode('automatic'); setProfile(null); });
    }
    PROFILES.forEach((item, index) => add(
      { id: `profile-${item.id}`, title: `Switch to ${item.name} Profile`, subtitle: profile === item.id ? 'Currently active' : 'Use its widgets and appearance', symbol: item.symbol, category: 'Profile', keywords: ['smart', 'mode', item.name], priority: 81 + index },
      () => { setProfileMode('manual'); setProfile(item.id); },
    ));
    if (profileMode !== 'off') {
      add({ id: 'profiles-off', title: 'Turn Smart Profiles Off', subtitle: 'Restore your standard notch setup', symbol: 'circle.slash', category: 'Profile', keywords: ['disable', 'default', 'mode'], priority: 89 },
        () => { setProfileMode('off'); setProfile(null); });
    }

    SETTINGS_PAGES.forEach((page, index) => add(
      { id: `settings-${page.id}`, title: `Open ${page.title} settings`, subtitle: page.subtitle, symbol: page.symbol, category: 'Settings', keywords: ['preferences', page.id], priority: 110 + index },
      () => undefined,
    ));
    return list;
  }, [isEnabled, focus, tabs, clipboard, captures, shelf, profileMode, profile, loadedAt, setTab, perform, startFocus, toggleFocusRunning, buddy.glasses, buddy.breaks, logWater, takeBreak]);

  const results = useMemo(() => searchCommands(query, commandList) as Array<Command & { run: Run }>, [query, commandList]);

  const setQuery = useCallback((value: string) => {
    setQueryState(value);
    setSelected(0);
  }, []);
  const openPalette = useCallback(() => {
    setQueryState('');
    setSelected(0);
    setPaletteOpen(true);
  }, []);
  const closePalette = useCallback(() => {
    setPaletteOpen(false);
    setQueryState('');
    setSelected(0);
  }, []);
  const moveSelection = useCallback((offset: number) => {
    setSelected((current) => {
      if (results.length === 0) return 0;
      const next = (current + offset) % results.length;
      return next >= 0 ? next : next + results.length;
    });
  }, [results.length]);
  const runCommand = useCallback((command: { run: Run }) => {
    command.run();
    closePalette();
  }, [closePalette]);

  return {
    setRoot, tick, loadedAt,
    // panel
    tab: shownTab, setTab, tabAdvances, tabs, isEnabled, accent: effectiveAccent, accentHex: accentHex(effectiveAccent), setAccent,
    activeProfile, panelWidth: activeProfile?.width ?? 520, panelStyle: activeProfile?.style ?? 'gradient',
    // live state
    agents, agentStatus, toggleAgent, toggleAttention,
    build, runBuild, meeting, setMeeting, meetingIn: Math.max(MEETING_IN - tick, 0),
    focus, startFocus, toggleFocusRunning, cancelFocus,
    buddy, buddyEnergy: buddyEnergy(buddy.stretch), buddyNeedsBreak, workAnHour, logWater, removeWater, takeBreak, snoozeBuddy,
    music, track: TRACKS[music.track], playPause, nextTrack, previousTrack,
    events, setEvents, banner, files, setFiles, startDownload,
    captures, setCaptures, draft, setDraft, saveDraft, pasteIntoDraft,
    clipboard, setClipboard, clipboardPaused, setClipboardPaused,
    shelf, setShelf, addToShelf,
    feedback, perform,
    // palette
    paletteOpen, openPalette, closePalette, query, setQuery, results, selected, setSelected, moveSelection, runCommand,
    // agents tab
    usageRange, setUsageRange,
  };
}

export type Demo = Omit<ReturnType<typeof useDemo>, 'setRoot'>;

const AGENT_STATUS: Record<AgentId, string> = {
  claude: 'Editing PeekView.swift',
  codex: 'Running tests',
  gemini: 'Reading files',
  ollama: 'Summarising local changes',
};

export const isLink = (text: string) => /^[a-z][a-z0-9+.-]*:\/\//i.test(text.trim());

export function clipboardDetail(item: { kind: 'text' | 'link' | 'image'; text: string; bytes?: number }) {
  if (item.kind === 'image') return `Image · ${byteString(item.bytes ?? 0)}`;
  if (item.kind === 'link') return 'Link';
  return `Text · ${item.text.length} character${item.text.length === 1 ? '' : 's'}`;
}

export const clipboardSymbol = (kind: 'text' | 'link' | 'image') =>
  kind === 'image' ? 'photo' : kind === 'link' ? 'link' : 'text.alignleft';

/** `QuickCaptureItem.detail`: "Link", or when it was saved. */
export function captureDetail(item: { text: string; ago: number }, loadedAt: Date | null) {
  if (isLink(item.text)) return 'Link';
  if (!loadedAt) return '';
  // Seconds before the page loaded; a capture saved here stores minus the
  // tick it was saved on, which lands it after.
  const saved = new Date(loadedAt.getTime() - item.ago * 1000);
  return `${saved.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })} at ${saved.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}`;
}
