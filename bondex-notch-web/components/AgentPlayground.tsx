'use client';

import { useEffect, useState } from 'react';

type AgentId = 'codex' | 'claude' | 'gemini' | 'ollama';

const agents: Array<{ id: AgentId; name: string; status: string }> = [
  { id: 'codex', name: 'Codex', status: 'Building the interaction demo' },
  { id: 'claude', name: 'Claude Code', status: 'Running the test suite' },
  { id: 'gemini', name: 'Gemini', status: 'Reviewing accessibility' },
  { id: 'ollama', name: 'Ollama', status: 'Summarising local changes' },
];

const claudeCodePixels = [
  '..XXXXXXXXXXXX..',
  '..XXXXXXXXXXXX..',
  '..XX.XXXXXX.XX..',
  '..XX.XXXXXX.XX..',
  'XXXXXXXXXXXXXXXX',
  'XXXXXXXXXXXXXXXX',
  '..XXXXXXXXXXXX..',
  '..XXXXXXXXXXXX..',
  '...X.X....X.X...',
  '...X.X....X.X...',
].join('');

function ClaudeCodeMark() {
  return (
    <span className="claude-code-mark" aria-hidden="true">
      {[...claudeCodePixels].map((pixel, index) => (
        <i className={pixel === 'X' ? 'is-on' : undefined} key={index} />
      ))}
    </span>
  );
}

function formatTime(totalSeconds: number) {
  const minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0');
  const seconds = (totalSeconds % 60).toString().padStart(2, '0');
  return `${minutes}:${seconds}`;
}

export default function AgentPlayground() {
  const [active, setActive] = useState<Set<AgentId>>(() => new Set(['codex']));
  const [elapsed, setElapsed] = useState<Record<AgentId, number>>({
    codex: 18,
    claude: 0,
    gemini: 0,
    ollama: 0,
  });
  const [buildState, setBuildState] = useState<'idle' | 'running' | 'done'>('idle');
  const [buildProgress, setBuildProgress] = useState(0);

  useEffect(() => {
    const timer = window.setInterval(() => {
      setElapsed((current) => {
        const next = { ...current };
        active.forEach((id) => { next[id] += 1; });
        return next;
      });
    }, 1000);

    return () => window.clearInterval(timer);
  }, [active]);

  useEffect(() => {
    if (buildState !== 'running') return;

    const timer = window.setInterval(() => {
      setBuildProgress((current) => Math.min(current + 2, 100));
    }, 90);
    const completionTimer = window.setTimeout(() => {
      setBuildProgress(100);
      setBuildState('done');
    }, 4500);

    return () => {
      window.clearInterval(timer);
      window.clearTimeout(completionTimer);
    };
  }, [buildState]);

  const toggleAgent = (id: AgentId) => {
    const isStarting = !active.has(id);
    if (isStarting) setElapsed((times) => ({ ...times, [id]: 0 }));

    setActive((current) => {
      const next = new Set(current);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  };

  const runAll = () => {
    setElapsed({ codex: 0, claude: 0, gemini: 0, ollama: 0 });
    setActive(new Set(agents.map(({ id }) => id)));
  };

  const reset = () => {
    setActive(new Set());
    setElapsed({ codex: 0, claude: 0, gemini: 0, ollama: 0 });
    setBuildState('idle');
    setBuildProgress(0);
  };

  const runBuild = () => {
    if (buildState === 'running') return;
    setBuildProgress(0);
    setBuildState('running');
  };

  return (
    <div className="product-shot product-shot--agents" aria-label="Interactive Bondex agent activity demo">
      <span className="shot-notch" aria-hidden="true" />
      <div className="shot-panel agent-demo">
        <div className="shot-topline">
          <span>Interactive demo</span>
          <span className={`shot-status${active.size === 0 ? ' is-idle' : ''}`}>
            <i /> {active.size} {active.size === 1 ? 'agent' : 'agents'} active
          </span>
        </div>

        <div className="agent-demo__controls">
          <span>Tap an agent to toggle it</span>
          <span>
            <button type="button" onClick={runAll}>Run all</button>
            <button type="button" onClick={reset}>Reset</button>
          </span>
        </div>

        <div className="agent-list">
          {agents.map((agent) => {
            const isActive = active.has(agent.id);
            return (
              <button
                type="button"
                className={`agent-row${isActive ? ' is-active' : ''}`}
                aria-pressed={isActive}
                onClick={() => toggleAgent(agent.id)}
                key={agent.id}
              >
                <span className={`agent-orb agent-orb--${agent.id}`} aria-hidden="true">
                  {agent.id === 'claude' && <ClaudeCodeMark />}
                </span>
                <span>
                  <b>{agent.name}</b>
                  <small>{isActive ? agent.status : 'Tap to start'}</small>
                </span>
                <time>{isActive ? formatTime(elapsed[agent.id]) : 'Start'}</time>
              </button>
            );
          })}
        </div>

        <button
          type="button"
          className={`live-task live-task--button${buildState === 'done' ? ' is-done' : ''}`}
          onClick={runBuild}
          aria-label={buildState === 'running' ? `Build ${buildProgress}% complete` : 'Run a simulated live build'}
        >
          <span className="live-task__top">
            <span>
              <i>↗</i>
              <b>{buildState === 'idle' ? 'Try a live build' : 'Building release'}</b>
              <small>{buildState === 'idle' ? 'Tap to start' : buildState === 'done' ? 'Build complete' : 'Running tests'}</small>
            </span>
            <strong>{buildState === 'idle' ? 'Run' : `${buildProgress}%`}</strong>
          </span>
          <span className="progress" aria-hidden="true">
            <i style={{ width: `${buildProgress}%` }} />
          </span>
        </button>
      </div>
      <span className="shot-caption">Try it — every control is live.</span>
    </div>
  );
}
