'use client';

import Image from 'next/image';
import { type CSSProperties, type DragEvent, useEffect, useState } from 'react';

type AgentId = 'codex' | 'claude' | 'gemini' | 'ollama';
type TabId = 'home' | 'capture' | 'shortcuts' | 'music' | 'system' | 'live' | 'files' | 'activity' | 'clipboard' | 'shelf';
type Accent = 'ocean' | 'violet' | 'forest';
type Profile = 'Work' | 'Meeting' | 'Media' | 'Gaming';

const tabs: Array<{ id: TabId; label: string; icon: string }> = [
  { id: 'home', label: 'Home', icon: '⌘' },
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

const agents: Array<{ id: AgentId; name: string; status: string }> = [
  { id: 'codex', name: 'Codex', status: 'Refining the landing page' },
  { id: 'claude', name: 'Claude Code', status: 'Running the test suite' },
  { id: 'gemini', name: 'Gemini', status: 'Reviewing accessibility' },
  { id: 'ollama', name: 'Ollama', status: 'Summarising local changes' },
];

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

function AgentMark({ id }: { id: AgentId }) {
  return (
    <span className={`agent-orb agent-orb--${id}`} aria-hidden="true">
      {id === 'claude' && <ClaudeCodeMark />}
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
  const [active, setActive] = useState<Set<AgentId>>(() => new Set(['codex']));
  const [elapsed, setElapsed] = useState<Record<AgentId, number>>({ codex: 222, claude: 0, gemini: 0, ollama: 0 });
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
          { id: Date.now(), icon: '✦', title: `${agent.name} finished`, detail: `Worked for ${formatTime(elapsed[id])}`, time: 'Now' },
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
    setActive(new Set(['codex']));
    setElapsed({ codex: 222, claude: 0, gemini: 0, ollama: 0 });
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
                <AgentMark id={id} />
                <span><b>{agent.name} is working</b><small>{agent.status}</small></span>
                <time>{formatTime(elapsed[id])}</time>
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
          <div><button type="button" onClick={runBuild}>Run build</button><button type="button" onClick={startDownload}>Download</button><button type="button" onClick={openCommandPalette}>Commands</button></div>
        </div>
        <div className="real-control-block real-control-block--accent">
          <span className="real-control-label">Accent</span>
          <span className="real-swatches" aria-label="Accent color">{(['ocean', 'violet', 'forest'] as Accent[]).map((color) => <button type="button" className={accent === color ? 'is-active' : ''} style={{ '--swatch': accentColors[color] } as CSSProperties} onClick={() => setAccent(color)} aria-label={`${color} accent`} key={color} />)}</span>
        </div>
      </div>
      <p className="real-demo-note">Ten live tabs · local-only demo · drop files onto Shelf</p>
    </div>
  );
}
