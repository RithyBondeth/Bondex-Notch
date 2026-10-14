'use client';

import { type CSSProperties, useRef, useState } from 'react';
import { ACCENTS, AGENTS } from './panel/model';
import NotchSurface, { type SurfaceState, peekFor } from './panel/NotchSurface';
import useFitZoom from './panel/useFitZoom';
import { useDemo } from './panel/useDemo';

/**
 * The interactive tour: the same panel as the hero, open and pinned, with
 * controls for the things that happen to it in the real app — agents
 * starting, stopping and asking for you, a build reporting progress, a
 * download landing. Every figure is sample data shaped like the app's.
 */
export default function AgentPlayground() {
  // Reset starts the demo over from its seed by remounting it.
  const [run, setRun] = useState(0);
  return <Playground key={run} onReset={() => setRun((current) => current + 1)} />;
}

function Playground({ onReset }: { onReset: () => void }) {
  const { setRoot, ...demo } = useDemo({ agents: ['claude', 'codex'], build: true, meeting: true });
  const [state, setState] = useState<SurfaceState>('expanded');
  const stage = useRef<HTMLDivElement>(null);
  const zoom = useFitZoom(stage, 560);

  const idle: SurfaceState = peekFor(demo) ? 'peek' : 'collapsed';
  const shown: SurfaceState = state === 'expanded' ? 'expanded' : idle;
  const open = () => setState('expanded');
  const show = (tab: Parameters<typeof demo.setTab>[0]) => {
    demo.closePalette();
    demo.setTab(tab);
    open();
  };

  return (
    <div ref={setRoot} className="product-shot product-shot--agents real-product" style={{ "--demo-accent": demo.accentHex } as CSSProperties} aria-label="Interactive Bondex Notch product demo">
      <div className="real-demo-top">
        <span className="real-demo-top__status"><i /><span><b>Interactive app preview</b><small>The Mac panel, drawn at its real size</small></span></span>
        <button type="button" onClick={onReset}>↺ Reset</button>
      </div>

      <div className="real-stage" ref={stage}>
        <div className="real-stage__notch" style={{ zoom }}>
          <NotchSurface
            demo={demo}
            state={shown}
            onClose={() => {
              demo.closePalette();
              setState('collapsed');
            }}
            onClick={() => {
              if (shown !== 'expanded') open();
            }}
            onKeyDown={(event) => {
              if (event.key === 'Escape' && demo.paletteOpen) demo.closePalette();
            }}
            onDropFiles={(names) => {
              demo.addToShelf(names);
              show('shelf');
            }}
          />
        </div>
        {shown !== 'expanded' && (
          <button type="button" className="real-stage__reopen" onClick={open}>Click the notch to open it again</button>
        )}
      </div>

      <div className="real-controls" aria-label="Demo controls">
        <div className="real-control-block real-control-block--agents">
          <span className="real-control-label">Agent signals</span>
          <div className="real-agent-toggles">
            {AGENTS.map((agent) => {
              const on = demo.agents.some((item) => item.id === agent.id);
              return (
                <button type="button" aria-pressed={on} className={on ? 'is-active' : ''} onClick={() => demo.toggleAgent(agent.id)} key={agent.id}>
                  {agent.name}
                </button>
              );
            })}
            <button
              type="button"
              aria-pressed={demo.agents.some((agent) => agent.attention)}
              className={`real-needs-you${demo.agents.some((agent) => agent.attention) ? ' is-active' : ''}`}
              onClick={demo.toggleAttention}
            >
              Needs you
            </button>
          </div>
        </div>
        <div className="real-control-block real-control-block--actions">
          <span className="real-control-label">Try an action</span>
          <div>
            <button type="button" onClick={() => { demo.runBuild(); show('home'); }}>Run build</button>
            <button type="button" onClick={() => { demo.startDownload(); show('files'); }}>Download</button>
            <button type="button" onClick={() => show('agents')}>Agent usage</button>
            <button type="button" onClick={() => { open(); demo.openPalette(); }}>Commands</button>
          </div>
        </div>
        <div className="real-control-block real-control-block--accent">
          <span className="real-control-label">Accent</span>
          <span className="real-swatches" role="group" aria-label="Accent colour">
            {ACCENTS.map((accent) => (
              <button
                type="button"
                className={demo.accent === accent.id ? 'is-active' : ''}
                aria-pressed={demo.accent === accent.id}
                style={{ '--swatch': accent.hex } as CSSProperties}
                onClick={() => demo.setAccent(accent.id)}
                aria-label={`${accent.name} accent`}
                title={accent.name}
                key={accent.id}
              />
            ))}
          </span>
        </div>
        <div className="real-control-block real-control-block--buddy">
          <span className="real-control-label">Wellness buddy</span>
          <div>
            <button type="button" onClick={() => { demo.workAnHour(); show('buddy'); }}>Work an hour</button>
            <button type="button" onClick={() => { demo.logWater(); show('buddy'); }}>Glass of water</button>
            <button type="button" onClick={() => { demo.takeBreak(); show('buddy'); }}>Take a break</button>
          </div>
        </div>
      </div>
      <p className="real-demo-note">Twelve tabs · sample usage figures · drop files onto the notch · click the buddy</p>
    </div>
  );
}
