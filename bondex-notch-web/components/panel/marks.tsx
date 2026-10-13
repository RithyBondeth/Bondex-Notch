import { type CSSProperties, useId } from 'react';
import { type AgentId, agentTint } from './model';

/* Every agent's mark, from the same geometry the app's AgentMarks builds, and
   the AgentOrb that wraps one while it works. */

const claudeRows = [
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
];

/** One rect per run of filled cells, so the grid draws as one shape. */
const claudePath = claudeRows
  .map((row, y) => {
    let d = '';
    let start = -1;
    for (let x = 0; x <= row.length; x += 1) {
      const on = row[x] === 'X';
      if (on && start < 0) start = x;
      if (!on && start >= 0) {
        d += `M${start} ${y}h${x - start}v1h${start - x}Z`;
        start = -1;
      }
    }
    return d;
  })
  .join('');

const roundRect = (x: number, y: number, w: number, h: number, rx: number, ry: number) =>
  `M${x + rx} ${y}H${x + w - rx}A${rx} ${ry} 0 0 1 ${x + w} ${y + ry}V${y + h - ry}A${rx} ${ry} 0 0 1 ${x + w - rx} ${y + h}H${x + rx}A${rx} ${ry} 0 0 1 ${x} ${y + h - ry}V${y + ry}A${rx} ${ry} 0 0 1 ${x + rx} ${y}Z`;
const ellipse = (cx: number, cy: number, rx: number, ry: number) =>
  `M${cx - rx} ${cy}A${rx} ${ry} 0 1 0 ${cx + rx} ${cy}A${rx} ${ry} 0 1 0 ${cx - rx} ${cy}Z`;

/* Ollama, and every agent Bondex has no mark for: ears, one rounded mass for
   head and body, eyes and muzzle cut out by the even-odd rule. */
const ollamaPath = [
  roundRect(24, 4, 16, 34, 8, 8),
  roundRect(60, 4, 16, 34, 8, 8),
  roundRect(16, 26, 68, 70, 26, 24),
  ellipse(36, 52, 6, 6),
  ellipse(64, 52, 6, 6),
  ellipse(50, 74, 14, 10),
].join('');

const codexLobes = Array.from({ length: 6 }, (_, lobe) => {
  const angle = ((15 + lobe * 60) * Math.PI) / 180;
  return [50 + 26 * Math.cos(angle), 50 + 26 * Math.sin(angle)] as const;
});

export function aspect(id: AgentId) {
  return id === 'claude' ? 1.6 : 1;
}

/** The agent's bare mark in its own tint, as the app's PixelMark draws it. */
export function PixelMark({ id, width, style }: { id: AgentId; width: number; style?: CSSProperties }) {
  const mask = useId();
  const tint = agentTint(id);
  const height = width / aspect(id);
  const common = { width, height, fill: tint, 'aria-hidden': true, style: { display: 'block', flex: 'none', ...style } } as const;

  if (id === 'claude') {
    return <svg viewBox="0 0 16 10" shapeRendering="crispEdges" {...common}><path d={claudePath} /></svg>;
  }
  if (id === 'codex') {
    return (
      <svg viewBox="0 0 100 100" {...common}>
        <mask id={mask}>
          <rect width="100" height="100" fill="#fff" />
          <path d="M27.37 36.68 34.89 50.41 27.37 64.13M53.35 64.13H72.3" fill="none" stroke="#000" strokeWidth="7.68" strokeLinecap="round" strokeLinejoin="round" />
        </mask>
        <g mask={`url(#${mask})`}>
          <circle cx="50" cy="50" r="30" />
          {codexLobes.map(([cx, cy]) => <circle key={`${cx}`} cx={cx.toFixed(2)} cy={cy.toFixed(2)} r="25.13" />)}
        </g>
      </svg>
    );
  }
  if (id === 'gemini') {
    return <svg viewBox="0 0 1 1" {...common}><path d="M.5 0Q.5 .5 1 .5Q.5 .5 .5 1Q.5 .5 0 .5Q.5 .5 .5 0Z" /></svg>;
  }
  return <svg viewBox="0 0 100 100" fillRule="evenodd" {...common}><path d={ollamaPath} /></svg>;
}

/**
 * The app's AgentOrb: the mark inside a ring whose arc sweeps while the agent
 * works. Waiting on you, the ring is whole, amber and pulsing.
 */
export function AgentOrb({
  id,
  size,
  working = true,
  attention = false,
}: {
  id: AgentId;
  size: number;
  working?: boolean;
  attention?: boolean;
}) {
  const line = Math.max(size * 0.075, 1.2);
  const radius = (size - line) / 2;
  const circumference = 2 * Math.PI * radius;
  const mode = attention ? 'attention' : working ? 'working' : 'still';
  return (
    <span
      className="ap-orb"
      data-mode={mode}
      style={{ width: size, height: size, '--tint': agentTint(id) } as CSSProperties}
      aria-hidden="true"
    >
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        <circle className="ap-orb__track" cx={size / 2} cy={size / 2} r={radius} strokeWidth={line} />
        <circle
          className="ap-orb__sweep"
          cx={size / 2}
          cy={size / 2}
          r={radius}
          strokeWidth={line}
          strokeDasharray={attention ? undefined : `${circumference * 0.28} ${circumference}`}
        />
      </svg>
      <span className="ap-orb__glyph">
        <PixelMark id={id} width={size * (aspect(id) > 1 ? 0.62 : 0.52)} />
      </span>
    </span>
  );
}
