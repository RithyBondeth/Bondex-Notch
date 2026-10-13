'use client';

import Image from 'next/image';
import { type CSSProperties, type HTMLAttributes, useEffect, useRef, useState } from 'react';
import AppPanel, { AudioBars, EventIcon, NOTCH_WIDTH } from './AppPanel';
import { AgentOrb } from './marks';
import { agentTint, clockString } from './model';
import Sym from './Symbol';
import { type Demo, type NotchEvent, type WorkingAgent, EVENT_KINDS } from './useDemo';

/* The panel's silhouette in its three sizes, as NotchRootView draws it: flush
   with the top edge, concave fillets where it meets the menu bar, and a peek
   that is a strip either side of the camera housing — never over it. */

export type SurfaceState = 'collapsed' | 'peek' | 'expanded';

export type Peek =
  | { kind: 'banner'; event: NotchEvent }
  | { kind: 'agent'; agents: WorkingAgent[] }
  | { kind: 'focus' }
  | { kind: 'meeting' }
  | { kind: 'live' }
  | { kind: 'media' };

/** `NotchViewModel.peekContent`, in its order of precedence. */
export function peekFor(demo: Demo): Peek | null {
  if (demo.banner) return { kind: 'banner', event: demo.banner };
  if (demo.agents.some((agent) => agent.attention)) return { kind: 'agent', agents: demo.agents };
  if (demo.focus) return { kind: 'focus' };
  if (demo.meeting && demo.meetingIn > 0) return { kind: 'meeting' };
  if (demo.build && demo.isEnabled('live')) return { kind: 'live' };
  if (demo.agents.length > 0) return { kind: 'agent', agents: demo.agents };
  if (demo.music.playing && demo.isEnabled('music')) return { kind: 'media' };
  return null;
}

/** `NotchGeometry`: every peek is the notch plus two wings. */
function peekWidth(peek: Peek) {
  switch (peek.kind) {
    case 'banner': return Math.max(NOTCH_WIDTH + 300, 440);
    case 'live':
    case 'meeting': return Math.max(NOTCH_WIDTH + 260, 400);
    case 'focus': return Math.max(NOTCH_WIDTH + 165, 310);
    case 'agent': return Math.max(NOTCH_WIDTH + 120 + (peek.agents.length - 1) * 50, 240);
    case 'media': return Math.max(NOTCH_WIDTH + 120, 240);
  }
}

const NOTCH_HEIGHT = 32;

export default function NotchSurface({
  demo,
  state,
  onClose,
  onDropFiles,
  ...rest
}: {
  demo: Demo;
  state: SurfaceState;
  onClose: () => void;
  onDropFiles?: (names: string[]) => void;
} & HTMLAttributes<HTMLDivElement>) {
  const panel = useRef<HTMLDivElement>(null);
  const [panelHeight, setPanelHeight] = useState<number | null>(null);
  const [dropTargeted, setDropTargeted] = useState(false);
  const peek = peekFor(demo);
  const shownState: SurfaceState = state === 'peek' && !peek ? 'collapsed' : state;

  /* The expanded panel is as tall as its content, measured. The panel keeps
     its full width inside the clip throughout, so the silhouette growing
     around it only reveals it and never reflows it. */
  useEffect(() => {
    const element = panel.current;
    if (!element) return;
    const measure = () => setPanelHeight(Math.ceil(element.offsetHeight));
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const size = shownState === 'expanded'
    ? { width: demo.panelWidth, height: panelHeight ?? 260, radius: 20 }
    : shownState === 'peek' && peek
      ? { width: peekWidth(peek), height: NOTCH_HEIGHT, radius: 15 }
      : { width: NOTCH_WIDTH, height: NOTCH_HEIGHT, radius: 10 };

  return (
    <div
      {...rest}
      className={`ap-surface${rest.className ? ` ${rest.className}` : ''}`}
      data-state={shownState}
      data-style={demo.panelStyle}
      data-drop={dropTargeted || undefined}
      style={{ '--accent': demo.accentHex, ...rest.style } as CSSProperties}
      onDragOver={onDropFiles ? (event) => { event.preventDefault(); setDropTargeted(true); } : undefined}
      onDragLeave={onDropFiles ? () => setDropTargeted(false) : undefined}
      onDrop={onDropFiles ? (event) => {
        event.preventDefault();
        setDropTargeted(false);
        onDropFiles(Array.from(event.dataTransfer.files).map((file) => file.name));
      } : undefined}
    >
      <div
        className="ap-surface__body"
        style={{ width: size.width, height: size.height, borderRadius: `0 0 ${size.radius}px ${size.radius}px` }}
      >
        <span className="ap-surface__rim" aria-hidden="true" />
        <div className="ap-surface__clip">
          <div className="ap-surface__peek" aria-hidden={shownState !== 'peek'}>
            {peek && <PeekContent demo={demo} peek={peek} width={peekWidth(peek)} />}
          </div>
          <div className="ap-surface__panel" ref={panel} aria-hidden={shownState !== 'expanded'} inert={shownState !== 'expanded'}>
            <AppPanel demo={demo} onClose={onClose} />
          </div>
        </div>
      </div>
      <span className="ap-surface__camera" aria-hidden="true" />
    </div>
  );
}

/* ── PeekView ────────────────────────────────────────────── */

function PeekContent({ demo, peek, width }: { demo: Demo; peek: Peek; width: number }) {
  const wing = (width - NOTCH_WIDTH) / 2;
  const accent = demo.accentHex;
  let leading: React.ReactNode = null;
  let trailing: React.ReactNode = null;

  switch (peek.kind) {
    case 'banner': {
      const kind = EVENT_KINDS[peek.event.kind];
      leading = (
        <span className="ap-peek__badge" style={{ background: `color-mix(in srgb, ${kind.tint} 16%, transparent)` }}>
          <EventIcon event={peek.event} size={12} />
        </span>
      );
      trailing = (
        <span className="ap-peek__lines ap-peek__lines--banner">
          <b>{peek.event.title}</b>
          {peek.event.subtitle && <small>{peek.event.subtitle}</small>}
        </span>
      );
      break;
    }
    case 'agent': {
      const several = peek.agents.length > 1;
      const columns: WorkingAgent[][] = [];
      for (let index = 0; index < peek.agents.length; index += 2) columns.push(peek.agents.slice(index, index + 2));
      leading = (
        <span className="ap-peek__marks">
          {peek.agents.map((agent) => <AgentOrb key={agent.id} id={agent.id} size={21} attention={agent.attention} />)}
        </span>
      );
      trailing = (
        <span className="ap-peek__clocks">
          {columns.map((column, index) => (
            <span key={index}>
              {column.map((agent) => (
                <b key={agent.id} className={several ? 'is-compact' : undefined} style={{ color: agent.attention ? 'var(--ap-attention)' : agentTint(agent.id) }}>
                  {agent.attention ? 'Needs you' : clockString(demo.tick - agent.since)}
                </b>
              ))}
            </span>
          ))}
        </span>
      );
      break;
    }
    case 'focus':
      leading = (
        <span className="ap-peek__ring" style={{ color: accent }}>
          <PeekRing value={demo.focus ? 1 - demo.focus.remaining / (25 * 60) : 0} tint={accent} />
          <Sym name="timer" size={8} />
        </span>
      );
      trailing = <b className="ap-peek__value">{clockString(demo.focus?.remaining ?? 0)}</b>;
      break;
    case 'meeting':
      leading = <span className="ap-peek__icon" style={{ color: '#4a9efa' }}><Sym name="calendar.badge.clock" size={11} /></span>;
      // Titles stay private in the peek by default: it may be on a shared screen.
      trailing = (
        <span className="ap-peek__lines">
          <b className="is-footnote">Upcoming meeting</b>
          <small>In {Math.ceil(demo.meetingIn / 60)} min</small>
        </span>
      );
      break;
    case 'live':
      leading = (
        <span className="ap-peek__ring ap-peek__ring--filled" style={{ color: accent }}>
          <PeekRing value={demo.build?.progress ?? 0} tint={accent} inset />
        </span>
      );
      trailing = (
        <span className="ap-peek__lines">
          <b>Building release</b>
          <small>Running tests</small>
        </span>
      );
      break;
    case 'media':
      leading = (
        <span className="ap-peek__art">
          <Image src={demo.track.artwork} alt="" width={42} height={42} />
        </span>
      );
      trailing = <AudioBars playing={demo.music.playing} tint={accent} />;
      break;
  }

  return (
    <div className="ap-peek" style={{ width, gridTemplateColumns: `${wing}px ${NOTCH_WIDTH}px ${wing}px` }}>
      <span className="ap-peek__wing">{leading}</span>
      <span aria-hidden="true" />
      <span className="ap-peek__wing ap-peek__wing--trailing">{trailing}</span>
    </div>
  );
}

function PeekRing({ value, tint, inset = false }: { value: number; tint: string; inset?: boolean }) {
  const size = inset ? 16 : 22;
  const line = 2.2;
  const r = (size - line) / 2;
  const c = 2 * Math.PI * r;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" strokeWidth={line} stroke="rgba(255,255,255,.12)" />
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" strokeWidth={line} stroke={tint} strokeDasharray={`${c * value} ${c}`} strokeLinecap="round" transform={`rotate(-90 ${size / 2} ${size / 2})`} />
    </svg>
  );
}
