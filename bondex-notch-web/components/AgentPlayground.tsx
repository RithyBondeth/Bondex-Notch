'use client';

import { type CSSProperties, type DragEvent, useEffect, useState } from 'react';

type AgentId = 'codex' | 'claude' | 'gemini' | 'ollama';
type TabId = 'home' | 'music' | 'system' | 'live' | 'files' | 'activity' | 'shelf';
type Accent = 'ocean' | 'violet' | 'forest';

const tabs: Array<{ id: TabId; label: string; icon: string }> = [
  { id: 'home', label: 'Home', icon: '⌘' },
  { id: 'music', label: 'Music', icon: '♪' },
  { id: 'system', label: 'System', icon: '◴' },
  { id: 'live', label: 'Live', icon: '⌁' },
  { id: 'files', label: 'Files', icon: '↓' },
  { id: 'activity', label: 'Activity', icon: '●' },
  { id: 'shelf', label: 'Shelf', icon: '▱' },
];

const agents: Array<{ id: AgentId; name: string; status: string }> = [
  { id: 'codex', name: 'Codex', status: 'Refining the landing page' },
  { id: 'claude', name: 'Claude Code', status: 'Running the test suite' },
  { id: 'gemini', name: 'Gemini', status: 'Reviewing accessibility' },
  { id: 'ollama', name: 'Ollama', status: 'Summarising local changes' },
];

const tracks = [
  { title: 'Weightless', artist: 'Marconi Union', album: 'Ambient Transmissions', source: 'Music' },
  { title: 'Midnight Drive', artist: 'The Electric Seas', album: 'Blue Hours', source: 'Spotify' },
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
  const [musicPosition, setMusicPosition] = useState(192);
  const [trackIndex, setTrackIndex] = useState(0);
  const [downloadState, setDownloadState] = useState<'idle' | 'running' | 'done'>('idle');
  const [downloadBytes, setDownloadBytes] = useState(0);
  const [shelfItems, setShelfItems] = useState(['Launch brief.pdf', 'Hero artwork.png']);
  const [isDropping, setIsDropping] = useState(false);
  const [systemTick, setSystemTick] = useState(0);
  const [events, setEvents] = useState([
    { id: 1, icon: '↓', title: 'design-review.sketch', detail: 'Download complete · 184 MB', time: 'Just now' },
    { id: 2, icon: '♪', title: 'Weightless', detail: 'Marconi Union', time: '2m' },
  ]);

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
    const timer = window.setInterval(() => setMusicPosition((current) => (current + 1) % 489), 1000);
    return () => window.clearInterval(timer);
  }, [musicPlaying]);

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

  const resetDemo = () => {
    setTab('home');
    setActive(new Set(['codex']));
    setElapsed({ codex: 222, claude: 0, gemini: 0, ollama: 0 });
    setBuildState('running');
    setBuildProgress(72);
    setMusicPlaying(true);
    setMusicPosition(192);
    setDownloadState('idle');
    setDownloadBytes(0);
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

      {buildState !== 'idle' && (
        <button type="button" className="real-card real-live-card" onClick={() => setTab('live')}>
          <span className="real-live-icon">↗</span>
          <span><b>Building release</b><small>{buildState === 'done' ? 'Build complete' : `Running tests · ${buildProgress}%`}</small></span>
          <span className="real-meter"><i style={{ width: `${buildProgress}%` }} /></span>
        </button>
      )}

      <div className="real-metrics">
        {metric('CPU', cpu)}
        {metric('Memory', memory, 'warm')}
        {metric('100%', 100, 'green')}
        <div className="real-metric real-network"><b><i>↓</i> {down}</b><b><i>↑</i> 118 KB/s</b><small>Network</small></div>
      </div>
    </div>
  );

  const musicView = (
    <div className="real-player">
      <span className="real-art"><i>{track.title.slice(0, 1)}</i></span>
      <div className="real-player__body">
        <span><b>{track.title}</b><small>{track.artist} — {track.album}</small><em>{track.source}</em></span>
        <input aria-label="Track position" type="range" min="0" max="489" value={musicPosition} onChange={(event) => setMusicPosition(Number(event.target.value))} />
        <span className="real-times"><small>{formatTime(musicPosition)}</small><small>08:09</small></span>
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

  const views: Record<TabId, React.ReactNode> = {
    home: homeView,
    music: musicView,
    system: <div className="real-system">{metric('CPU', cpu)}{metric('Memory', memory, 'warm')}{metric('Battery', 100, 'green')}<div className="real-metric real-network"><b><i>↓</i> {down}</b><b><i>↑</i> 118 KB/s</b><small>Network</small></div></div>,
    live: liveView,
    files: filesView,
    activity: activityView,
    shelf: shelfView,
  };

  return (
    <div className="product-shot product-shot--agents real-product" style={{ '--demo-accent': accentColors[accent] } as CSSProperties} aria-label="Interactive Bondex Notch product demo">
      <div className="real-menubar" aria-hidden="true"><span>Bondex</span><span>● ● ●</span></div>
      <div className="real-panel">
        <span className="real-panel__camera" aria-hidden="true"><i /></span>
        <div className="real-panel__content">
          <div className="real-tabs" role="tablist" aria-label="Bondex widgets">
            {tabs.map((item) => <button type="button" role="tab" aria-selected={tab === item.id} className={tab === item.id ? 'is-active' : ''} onClick={() => setTab(item.id)} key={item.id}><i>{item.icon}</i>{tab === item.id && <span>{item.label}</span>}</button>)}
            <button type="button" className="real-close" aria-label="Collapse panel">×</button>
          </div>
          <div className="real-divider" />
          <div className="real-view" key={tab}>{views[tab]}</div>
        </div>
      </div>

      <div className="real-controls" aria-label="Demo controls">
        <span>Send a signal</span>
        <div>{agents.map((agent) => <button type="button" aria-pressed={active.has(agent.id)} className={active.has(agent.id) ? 'is-active' : ''} onClick={() => toggleAgent(agent.id)} key={agent.id}>{agent.name}</button>)}</div>
        <button type="button" onClick={runBuild}>Run build</button>
        <button type="button" onClick={startDownload}>Download</button>
        <span className="real-swatches" aria-label="Accent color">{(['ocean', 'violet', 'forest'] as Accent[]).map((color) => <button type="button" className={accent === color ? 'is-active' : ''} style={{ '--swatch': accentColors[color] } as CSSProperties} onClick={() => setAccent(color)} aria-label={`${color} accent`} key={color} />)}</span>
        <button type="button" onClick={resetDemo}>Reset</button>
      </div>
      <span className="shot-caption">Explore every tab · drop files onto Shelf · nothing is uploaded.</span>
    </div>
  );
}
