import type { ReactNode } from 'react';

/* Stand-ins for the SF Symbols the panel draws, by the same names the Swift
   code uses, so a view here reads like the view it copies. Drawn on a 24-unit
   grid and sized like a symbol: `size` is the point size the app passes to
   `.font(.system(size:))`, and the glyph lands at about that height. */

type Glyph = { body: ReactNode; stroke?: number; evenOdd?: boolean };

const round = (value: number) => value.toFixed(2);

/** A point `radius` from the centre of the grid, `degrees` clockwise from 12 o'clock. */
function polar(radius: number, degrees: number, cx = 12, cy = 12) {
  const angle = ((degrees - 90) * Math.PI) / 180;
  return `${round(cx + radius * Math.cos(angle))} ${round(cy + radius * Math.sin(angle))}`;
}

const gear = (() => {
  let d = '';
  for (let tooth = 0; tooth < 8; tooth += 1) {
    const at = tooth * 45;
    d += `${tooth === 0 ? 'M' : 'L'}${polar(7.7, at - 16)} L${polar(10.7, at - 9)} L${polar(10.7, at + 9)} L${polar(7.7, at + 16)} `;
  }
  return `${d}Z M12 8.3a3.7 3.7 0 1 0 0 7.4a3.7 3.7 0 1 0 0-7.4Z`;
})();

/** A plus turned 45°, for marks cut out of a filled disc. */
function cross(cx: number, cy: number, arm: number, half: number) {
  const plus: Array<[number, number]> = [
    [half, arm], [half, half], [arm, half], [arm, -half], [half, -half], [half, -arm],
    [-half, -arm], [-half, -half], [-arm, -half], [-arm, half], [-half, half], [-half, arm],
  ];
  return `M${plus.map(([x, y]) => `${round(cx + (x - y) / Math.SQRT2)} ${round(cy + (x + y) / Math.SQRT2)}`).join(' L')}Z`;
}

const disc = (cx: number, cy: number, r: number) =>
  `M${cx} ${cy - r}a${r} ${r} 0 1 0 0 ${r * 2}a${r} ${r} 0 1 0 0-${r * 2}Z`;

const star = (cx: number, cy: number, r: number) => {
  const k = r * 0.16;
  return `M${cx} ${cy - r}C${cx + k} ${cy - k} ${cx + k} ${cy - k} ${cx + r} ${cy}C${cx + k} ${cy + k} ${cx + k} ${cy + k} ${cx} ${cy + r}C${cx - k} ${cy + k} ${cx - k} ${cy + k} ${cx - r} ${cy}C${cx - k} ${cy - k} ${cx - k} ${cy - k} ${cx} ${cy - r}Z`;
};

const glyphs: Record<string, Glyph> = {
  /* The wellness buddy's glyphs: the tab, its goals, and its badges. */
  'leaf.fill': {
    body: <path d="M20.6 3.4C11.9 3.1 4.9 6.8 4.5 14.4c-.1 1.7.3 3.2 1 4.5l-2.3 2.3 1.2 1.2 2.3-2.3c1.3.8 2.9 1.2 4.6 1.1 7.4-.5 10.4-8.6 9.3-17.8ZM7.7 17.3l8.9-8.9.9.9-8.9 8.9z" />,
    evenOdd: true,
  },
  'drop.fill': { body: <path d="M12 2.4c-.3 0-.6.2-.8.5C8.9 6.5 5.4 10.4 5.4 14.6a6.6 6.6 0 0 0 13.2 0c0-4.2-3.5-8.1-5.8-11.7-.2-.3-.5-.5-.8-.5Z" /> },
  'figure.walk': {
    body: <><circle cx="13.7" cy="4.3" r="1.3" /><path d="M12.9 8.6 11 14.6l3.3 2.6 1 4.4M11.7 12.2 8.6 14.1M13 9.1l2.6 2.6 3 .8M11 14.6l-2.1 3.3-2.7 2.8" /></>,
    stroke: 2.2,
  },
  'flame.fill': { body: <path d="M12.2 2.3c.7 3-1.4 4.7-3 6.6-1.5 1.9-2.8 4-2.8 6.5a5.7 5.7 0 0 0 11.4 0c0-2.6-1.2-4.6-2.4-6.1-.2 1.4-.8 2.5-1.8 3.1.3-3.8-.6-7.6-1.4-10.1Z" /> },
  'lock.fill': {
    body: <path d="M7 10.5V8a5 5 0 0 1 10 0v2.5h.6c.9 0 1.6.7 1.6 1.6v7.3c0 .9-.7 1.6-1.6 1.6H6.4c-.9 0-1.6-.7-1.6-1.6v-7.3c0-.9.7-1.6 1.6-1.6Zm2.3 0h5.4V8a2.7 2.7 0 0 0-5.4 0Z" />,
    evenOdd: true,
  },
  plus: { body: <path d="M12 5v14M5 12h14" />, stroke: 2.6 },
  minus: { body: <path d="M5 12h14" />, stroke: 2.6 },
  'bolt.heart.fill': {
    body: <path d="M12 20.5C6.6 16.4 3 13.2 3 9.3 3 6.7 5 4.7 7.5 4.7c1.8 0 3.4 1 4.5 2.5 1.1-1.5 2.7-2.5 4.5-2.5 2.5 0 4.5 2 4.5 4.6 0 3.9-3.6 7.1-9 11.2ZM12.9 7.6 9.4 12.5h2.4l-.8 4 3.6-5h-2.4z" />,
    evenOdd: true,
  },
  'camera.macro': {
    body: <path d="M6.5 5.5c1.6 0 3 .6 4 1.6L12 4l1.5 3.1c1-1 2.4-1.6 4-1.6 0 4-2.3 6.8-5.5 6.8S6.5 9.5 6.5 5.5ZM11.2 12.3h1.6v8.9h-1.6ZM12.8 18c.7-2.6 2.8-4.2 5.6-4.2-.4 2.8-2.6 4.8-5.6 4.8ZM11.2 18c-.7-2.6-2.8-4.2-5.6-4.2.4 2.8 2.6 4.8 5.6 4.8Z" />,
  },
  'laurel.leading': {
    body: <path d="M15.5 20.6C9.7 18.7 7 14 7.6 8.2M7.7 10.7c-1.9-.4-3-1.8-3.2-3.6 1.9.1 3.1 1.3 3.2 3.6ZM8.3 14.5c-2-.1-3.3-1.3-3.8-3.2 2 0 3.4 1.1 3.8 3.2ZM10.3 17.7c-1.9.4-3.5-.4-4.4-2.1 1.9-.4 3.5.4 4.4 2.1ZM8 7c-1.4-1.3-1.6-3.1-.9-4.7 1.4 1.2 1.7 2.9.9 4.7Z" />,
    stroke: 1.7,
  },
  'tree.fill': { body: <path d="M12 2.4 5.8 10.3h2.7l-3.7 5.3h5.8v5.9h2.8v-5.9h5.8l-3.7-5.3h2.7Z" /> },
  'crown.fill': { body: <path d="M3.4 8.1 7.9 11.8 12 4.9l4.1 6.9 4.5-3.7-1.7 10H5.1ZM5.2 19.8h13.6v1.9H5.2Z" /> },
  'gearshape.fill': { body: <path d={gear} />, evenOdd: true },
  magnifyingglass: { body: <><circle cx="10.4" cy="10.4" r="6.4" /><path d="M15.2 15.2 20.6 20.6" /></>, stroke: 2.7 },
  xmark: { body: <path d="M6.3 6.3 17.7 17.7M17.7 6.3 6.3 17.7" />, stroke: 2.7 },
  'square.grid.2x2.fill': {
    body: <><rect x="3" y="3" width="7.7" height="7.7" rx="2.1" /><rect x="13.3" y="3" width="7.7" height="7.7" rx="2.1" /><rect x="3" y="13.3" width="7.7" height="7.7" rx="2.1" /><rect x="13.3" y="13.3" width="7.7" height="7.7" rx="2.1" /></>,
  },
  'square.and.pencil': {
    body: <><path d="M11.2 4.6H6.6A2.6 2.6 0 0 0 4 7.2v10.2A2.6 2.6 0 0 0 6.6 20h10.2a2.6 2.6 0 0 0 2.6-2.6v-4.6" /><path d="M17.7 3.7a1.9 1.9 0 0 1 2.7 2.7l-7.6 7.6-3.6.9.9-3.6z" /></>,
    stroke: 2.1,
  },
  'bolt.square.fill': {
    body: <path d="M6.2 2.6h11.6a3.6 3.6 0 0 1 3.6 3.6v11.6a3.6 3.6 0 0 1-3.6 3.6H6.2a3.6 3.6 0 0 1-3.6-3.6V6.2a3.6 3.6 0 0 1 3.6-3.6ZM13.4 5.6 7.6 13.3h4.1l-1.1 5.2 5.9-7.9h-4.2z" />,
    evenOdd: true,
  },
  'music.note': {
    body: <path d="M10.3 3h2.3c.2 2.2 1.6 3.3 3.3 4.2 1.9 1 3.4 2.2 3.3 4.9-1-1.5-2.5-2.3-4.3-2.7-.9-.2-1.7-.5-2.3-1v9.1c0 2-1.7 3.5-3.7 3.5s-3.5-1.2-3.5-2.9c0-2 1.9-3.4 4-3.4.3 0 .6 0 .9.1z" />,
  },
  'gauge.medium': {
    body: <><circle cx="12" cy="12" r="8.9" /><path d="M12 13.2 15.7 8.4M6.6 12h1.2M16.2 12h1.2M12 6.6v1.2" /></>,
    stroke: 2.1,
  },
  'waveform.path.ecg': { body: <path d="M2 12.6h4.3l2.1-5.6 3.6 10.6 2.6-8.1 1.6 3.1H22" />, stroke: 2.2 },
  'arrow.down.circle.fill': {
    body: <path d={`${disc(12, 12, 10)}M10.9 6.6h2.2v7l2.6-2.6 1.5 1.5-5.2 5.2-5.2-5.2 1.5-1.5 2.6 2.6z`} />,
    evenOdd: true,
  },
  'arrow.down.circle': { body: <><circle cx="12" cy="12" r="9" /><path d="M12 7v9.6M8 12.7l4 4 4-4" /></>, stroke: 2 },
  'bell.fill': {
    body: <path d="M12 2.6c.8 0 1.5.7 1.5 1.5v.5c2.8.7 4.6 3.1 4.6 6.1v3.6l1.9 2.6c.5.7 0 1.6-.8 1.6H4.8c-.8 0-1.3-.9-.8-1.6l1.9-2.6v-3.6c0-3 1.8-5.4 4.6-6.1v-.5c0-.8.7-1.5 1.5-1.5ZM9.3 19.6h5.4a2.7 2.7 0 0 1-5.4 0Z" />,
  },
  'bell.slash': {
    body: <><path d="M17.8 14V10.8c0-3.4-2.4-6.1-5.8-6.1-1.5 0-2.8.5-3.8 1.4M6.2 9.4c-.1.4-.1.9-.1 1.4v3.6l-1.9 2.7h11.4M10 19.6a2.2 2.2 0 0 0 4 0" /><path d="M3.5 3.5l17 17" /></>,
    stroke: 1.9,
  },
  'doc.on.clipboard.fill': {
    body: <><path d="M9 2.6h4.4c.6 0 1 .4 1 1V4H16a2.1 2.1 0 0 1 2.1 2.1v1.3h-6.3a3.3 3.3 0 0 0-3.3 3.3V19H6.2a2.1 2.1 0 0 1-2.1-2.1V6.1A2.1 2.1 0 0 1 6.2 4H8v-.4c0-.6.4-1 1-1Z" /><rect x="10.1" y="9" width="10.2" height="12.6" rx="2.1" /></>,
  },
  'doc.on.clipboard': {
    body: <><path d="M14.6 5H16a2 2 0 0 1 2 2v1.2M8.2 19.5H6.4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h1.6M9 3.4h4.6v3H9z" /><rect x="10.5" y="9.6" width="9.4" height="11.6" rx="2" /></>,
    stroke: 1.8,
  },
  'tray.full.fill': {
    body: <path d="M7.4 5.2h9.2c.8 0 1.5.5 1.8 1.2l2.7 6.8v4.6a2.6 2.6 0 0 1-2.6 2.6H5.5a2.6 2.6 0 0 1-2.6-2.6v-4.6l2.7-6.8c.3-.7 1-1.2 1.8-1.2ZM5.3 13.4h3.6l.9 1.9h4.4l.9-1.9h3.6l-2.2-5.9H7.5ZM8.3 8.6h7.4v1.3H8.3ZM7.8 10.9h8.4v1.3H7.8Z" />,
    evenOdd: true,
  },
  tray: { body: <path d="M3.4 13.6 6 6.9c.3-.7 1-1.2 1.8-1.2h8.4c.8 0 1.5.5 1.8 1.2l2.6 6.7v3.6a2.4 2.4 0 0 1-2.4 2.4H5.8a2.4 2.4 0 0 1-2.4-2.4ZM3.6 13.6h4.8l1.1 2.1h5l1.1-2.1h4.8" />, stroke: 1.8 },
  timer: { body: <><circle cx="12" cy="13" r="8.1" /><path d="M12 13 15.3 9.7M12 2.6v2.3" /></>, stroke: 2.2 },
  'calendar.badge.clock': {
    body: <path d={`M5.6 3.6h11.2A2.6 2.6 0 0 1 19.4 6.2v5a6.4 6.4 0 0 0-8.2 8.2H5.6A2.6 2.6 0 0 1 3 16.8V6.2a2.6 2.6 0 0 1 2.6-2.6ZM4.8 8.4v8.3c0 .5.4.9.9.9h5c0-3.6 2.7-6.6 6.2-6.9V8.4ZM6.6 10h1.8v1.6H6.6ZM9.6 10h1.8v1.6H9.6ZM6.6 13h1.8v1.6H6.6Z${disc(17.4, 17.4, 5)}M16.8 14.6h1.3v2.6l1.7 1.1-.7 1.1-2.3-1.5z`} />,
    evenOdd: true,
  },
  'backward.fill': {
    body: <path d="M11.4 6.5v11c0 .8-.9 1.3-1.6.8L3.4 13a1.2 1.2 0 0 1 0-2l6.4-5.3c.7-.5 1.6 0 1.6.8ZM20.8 6.5v11c0 .8-.9 1.3-1.6.8L12.8 13a1.2 1.2 0 0 1 0-2l6.4-5.3c.7-.5 1.6 0 1.6.8Z" />,
  },
  'forward.fill': {
    body: <path d="M12.6 6.5v11c0 .8.9 1.3 1.6.8l6.4-5.3a1.2 1.2 0 0 0 0-2l-6.4-5.3c-.7-.5-1.6 0-1.6.8ZM3.2 6.5v11c0 .8.9 1.3 1.6.8L11.2 13a1.2 1.2 0 0 0 0-2L4.8 5.7c-.7-.5-1.6 0-1.6.8Z" />,
  },
  'play.fill': { body: <path d="M7.3 4.8v14.4c0 .9 1 1.5 1.8.9l10.6-7.2a1.1 1.1 0 0 0 0-1.8L9.1 3.9c-.8-.6-1.8 0-1.8.9Z" /> },
  'pause.fill': { body: <><rect x="6.1" y="4.6" width="4.2" height="14.8" rx="1.3" /><rect x="13.7" y="4.6" width="4.2" height="14.8" rx="1.3" /></> },
  sparkles: { body: <path d={`${star(10, 13.4, 7.6)}${star(18.4, 5.2, 3.1)}${star(18.6, 18.6, 2.2)}`} /> },
  sparkle: { body: <path d={star(12, 12, 9.6)} /> },
  'arrow.up': { body: <path d="M12 19.6V5.2M6.4 10.8 12 5.2l5.6 5.6" />, stroke: 2.5 },
  'arrow.down': { body: <path d="M12 4.4v14.4M6.4 13.2 12 18.8l5.6-5.6" />, stroke: 2.5 },
  pin: { body: <><path d="M9.2 3.4h5.6l-.6 5.4 3.2 3.8H6.6l3.2-3.8z" /><path d="M12 12.6v8" /></>, stroke: 1.9 },
  'pin.fill': { body: <><path d="M9 3h6l-.6 5.6 3.4 4H6.2l3.4-4z" /><rect x="11.1" y="12.2" width="1.8" height="8.6" rx=".9" /></> },
  link: {
    body: <><path d="M10.2 13.8a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7L12 6.3" /><path d="M13.8 10.2a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1.2-1.2" /></>,
    stroke: 2.2,
  },
  'note.text': { body: <><rect x="4" y="4" width="16" height="16" rx="3.2" /><path d="M8 9h8M8 12.4h8M8 15.8h5" /></>, stroke: 1.9 },
  'text.alignleft': { body: <path d="M4 6h16M4 10.3h11M4 14.6h16M4 18.9h9" />, stroke: 2.2 },
  photo: { body: <><rect x="3" y="5" width="18" height="14" rx="2.6" /><path d="m3.6 17 5-5 4 4 2.4-2.4 5.4 5.2" /><circle cx="16" cy="9.6" r="1.4" /></>, stroke: 1.9 },
  trash: {
    body: <><path d="M4.5 6.6h15M9.5 6.6V4.9c0-.7.6-1.3 1.3-1.3h2.4c.7 0 1.3.6 1.3 1.3v1.7" /><path d="m6.5 6.6.9 12.3c.1 1 .9 1.6 1.8 1.6h5.6c.9 0 1.7-.6 1.8-1.6l.9-12.3M10.2 10.4v6M13.8 10.4v6" /></>,
    stroke: 1.9,
  },
  'battery.100percent': {
    body: <path d="M5.5 6.6h12A3 3 0 0 1 20.5 9.6v4.8a3 3 0 0 1-3 3h-12a3 3 0 0 1-3-3V9.6a3 3 0 0 1 3-3Zm0 1.6c-.8 0-1.4.6-1.4 1.4v4.8c0 .8.6 1.4 1.4 1.4h12c.8 0 1.4-.6 1.4-1.4V9.6c0-.8-.6-1.4-1.4-1.4ZM6 9.8h11v4.4H6ZM21.5 10.2h.4c.6 0 1 .5 1 1v1.6c0 .5-.4 1-1 1h-.4Z" />,
    evenOdd: true,
  },
  'bolt.fill': { body: <path d="M13.7 2.4 5 13.7h6.1L9.8 21.6l9.2-11.7h-6.2z" /> },
  'powerplug.fill': { body: <path d="M7.6 2.6h1.8v4.2h5.2V2.6h1.8v4.2H18v3.8a6 6 0 0 1-4.7 5.9v4.9h-2.6v-4.9A6 6 0 0 1 6 10.6V6.8h1.6Z" /> },
  laptopcomputer: { body: <><rect x="4.4" y="5" width="15.2" height="10.6" rx="1.6" /><path d="M2 18.6h20" /></>, stroke: 1.9 },
  keyboard: {
    body: <path d="M4.6 6h14.8a2.6 2.6 0 0 1 2.6 2.6v6.8a2.6 2.6 0 0 1-2.6 2.6H4.6A2.6 2.6 0 0 1 2 15.4V8.6A2.6 2.6 0 0 1 4.6 6Zm0 1.6c-.6 0-1 .4-1 1v6.8c0 .6.4 1 1 1h14.8c.6 0 1-.4 1-1V8.6c0-.6-.4-1-1-1ZM5.4 9.2h1.8V11H5.4Zm3 0h1.8V11H8.4Zm3 0h1.8V11h-1.8Zm3 0h1.8V11h-1.8Zm3 0h1.8V11h-1.8ZM8 13h8v1.6H8Z" />,
    evenOdd: true,
  },
  computermouse: { body: <><rect x="6.8" y="2.8" width="10.4" height="18.4" rx="5.2" /><path d="M12 6.4v3" /></>, stroke: 1.9 },
  headphones: {
    body: <><path d="M4.2 15.4v-3.2a7.8 7.8 0 0 1 15.6 0v3.2" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" /><rect x="3" y="13.4" width="4.8" height="7.4" rx="1.9" /><rect x="16.2" y="13.4" width="4.8" height="7.4" rx="1.9" /></>,
  },
  'checkmark.circle.fill': { body: <path d={`${disc(12, 12, 10)}M10.6 16.2 6.5 12.1l1.6-1.6 2.5 2.5 5.3-5.3 1.6 1.6z`} />, evenOdd: true },
  'exclamationmark.triangle.fill': { body: <path d="M10.3 3.4c.8-1.3 2.6-1.3 3.4 0l8.4 14.6c.7 1.3-.2 2.9-1.7 2.9H3.6c-1.5 0-2.4-1.6-1.7-2.9ZM11 8.4h2l-.3 6.2h-1.4Zm1 7.7a1.2 1.2 0 1 0 0 2.4 1.2 1.2 0 0 0 0-2.4Z" />, evenOdd: true },
  'xmark.circle.fill': { body: <path d={`${disc(12, 12, 10)}${cross(12, 12, 4.6, 1.15)}`} />, evenOdd: true },
  cpu: {
    body: <><rect x="5.6" y="5.6" width="12.8" height="12.8" rx="2.4" /><rect x="9.4" y="9.4" width="5.2" height="5.2" rx=".8" fill="currentColor" stroke="none" /><path d="M9.4 2.6v3M14.6 2.6v3M9.4 18.4v3M14.6 18.4v3M2.6 9.4h3M2.6 14.6h3M18.4 9.4h3M18.4 14.6h3" /></>,
    stroke: 1.8,
  },
  command: {
    body: <path d="M9 9V6.6A2.4 2.4 0 1 0 6.6 9H17.4A2.4 2.4 0 1 0 15 6.6v10.8a2.4 2.4 0 1 0 2.4-2.4H6.6A2.4 2.4 0 1 0 9 17.4Z" />,
    stroke: 1.9,
  },
  'app.fill': { body: <rect x="3.4" y="3.4" width="17.2" height="17.2" rx="4.6" /> },
  return: { body: <path d="M19.4 5v6.4a2.6 2.6 0 0 1-2.6 2.6H5.4M9.6 9.8 5.4 14l4.2 4.2" />, stroke: 2.2 },
  'arrow.up.arrow.down': { body: <path d="M8 19V5.4M4.2 9.2 8 5.4l3.8 3.8M16 5v13.6M12.2 14.8l3.8 3.8 3.8-3.8" />, stroke: 2 },
  'sparkle.magnifyingglass': {
    body: <><circle cx="10.4" cy="10.4" r="7" fill="none" stroke="currentColor" strokeWidth="2" /><path d="M15.6 15.6 21 21" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" /><path d={star(10.4, 10.4, 3.8)} /></>,
  },
  'dollarsign.circle': {
    body: <><circle cx="12" cy="12" r="9.2" /><path d="M14.9 8.9c-.5-.9-1.6-1.4-2.9-1.4-1.7 0-2.9.9-2.9 2.1 0 2.9 5.9 1.5 5.9 4.4 0 1.3-1.3 2.2-3 2.2-1.4 0-2.6-.6-3-1.6M12 5.6v1.9M12 16.2v2.2" /></>,
    stroke: 1.8,
  },
  'chart.bar.fill': { body: <><rect x="3" y="12.4" width="4.6" height="8.6" rx="1.3" /><rect x="9.7" y="7.2" width="4.6" height="13.8" rx="1.3" /><rect x="16.4" y="3" width="4.6" height="18" rx="1.3" /></> },
  'folder.fill': { body: <path d="M3 6.6c0-1.1.9-2 2-2h4.3l2 2.2H19c1.1 0 2 .9 2 2v8.6c0 1.1-.9 2-2 2H5c-1.1 0-2-.9-2-2Z" /> },
  'arrow.clockwise': { body: <><path d="M19.4 12.4a7.4 7.4 0 1 1-2.4-6" /><path d="M19.6 3.6v4.6H15" /></>, stroke: 2.4 },
  'doc.fill': { body: <path d="M6.6 2.6h6.8l5.2 5.2v11.6a2 2 0 0 1-2 2H6.6a2 2 0 0 1-2-2V4.6c0-1.1.9-2 2-2Z" /> },
  'video.fill': { body: <><rect x="2.4" y="6" width="13.4" height="12" rx="2.8" /><path d="M16.8 10.4 21.6 7.4v9.2l-4.8-3Z" /></> },
  'mic.fill': {
    body: <><rect x="8.8" y="2.6" width="6.4" height="11.6" rx="3.2" /><path d="M5.6 11a6.4 6.4 0 0 0 12.8 0M12 17.6v3.6" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" /></>,
  },
  'briefcase.fill': {
    body: <path d="M9 4.4h6c.9 0 1.6.7 1.6 1.6v1.2H19a2.6 2.6 0 0 1 2.6 2.6v8.2A2.6 2.6 0 0 1 19 20.6H5A2.6 2.6 0 0 1 2.4 18V9.8A2.6 2.6 0 0 1 5 7.2h2.4V6c0-.9.7-1.6 1.6-1.6Zm.2 1.8v1h5.6v-1Z" />,
    evenOdd: true,
  },
  'play.circle.fill': { body: <path d={`${disc(12, 12, 10)}M9.8 7.6v8.8l7-4.4z`} />, evenOdd: true },
  'gamecontroller.fill': {
    body: <path d="M7.4 6.6h9.2c2.4 0 4.2 1.7 4.6 4.1l.8 5.1c.3 2-1.2 3.6-3 3.6-1 0-1.9-.5-2.5-1.3l-1-1.4H8.5l-1 1.4c-.6.8-1.5 1.3-2.5 1.3-1.8 0-3.3-1.6-3-3.6l.8-5.1c.4-2.4 2.2-4.1 4.6-4.1ZM7.4 9.4v1.5H5.9v1.4h1.5v1.5h1.4v-1.5h1.5v-1.4H8.8V9.4Zm8.8.2a1 1 0 1 0 0 2 1 1 0 0 0 0-2Zm-2 2.2a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z" />,
    evenOdd: true,
  },
  'wand.and.stars': { body: <><path d="m4 20 10-10" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" /><path d={`${star(17, 5.4, 3)}${star(19.6, 12.4, 2)}${star(10.4, 4, 1.8)}`} /></> },
  'circle.slash': { body: <><circle cx="12" cy="12" r="9" /><path d="M5.6 18.4 18.4 5.6" /></>, stroke: 2 },
  'slider.horizontal.3': {
    body: <><path d="M3 6.4h18M3 12h18M3 17.6h18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" /><circle cx="8" cy="6.4" r="2.4" /><circle cx="15.6" cy="12" r="2.4" /><circle cx="10" cy="17.6" r="2.4" /></>,
  },
  'person.crop.circle.badge.clock.fill': {
    body: <path d={`M12 2.6a9.4 9.4 0 0 1 9.3 8 7 7 0 0 0-10.4 10.6A9.4 9.4 0 0 1 12 2.6Zm0 3.4a3.2 3.2 0 1 0 0 6.4 3.2 3.2 0 0 0 0-6.4Z${disc(17.4, 17.4, 5)}M16.8 14.6h1.3v2.6l1.7 1.1-.7 1.1-2.3-1.5z`} />,
    evenOdd: true,
  },
  'paintbrush.pointed.fill': { body: <path d="M20.6 3.4c.5.5.4 1.3-.1 1.8l-8 8.6-2.3-2.3 8.6-8c.5-.5 1.3-.6 1.8-.1ZM9.2 12.6l2.2 2.2c-.2 3.2-2.5 5.6-6.1 5.8-1 .1-1.9 0-2.7-.2 1.4-1 1.6-2.3 1.9-3.6.5-2.3 2.1-4 4.7-4.2Z" /> },
  'lock.shield.fill': {
    body: <path d="M12 2.4 20 5.4v6.2c0 4.8-3.3 8.5-8 10-4.7-1.5-8-5.2-8-10V5.4Zm-2.4 8.4V9.6a2.4 2.4 0 0 1 4.8 0v1.2h.4c.4 0 .7.3.7.7v3.7c0 .4-.3.7-.7.7H9.2c-.4 0-.7-.3-.7-.7v-3.7c0-.4.3-.7.7-.7Zm1.3 0h2.2V9.6a1.1 1.1 0 0 0-2.2 0Z" />,
    evenOdd: true,
  },
};

/* The robot is Bondex's own glyph (RobotGlyph), drawn on a 16-unit grid. */
const robot = (
  <path d="M8 .2a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3ZM7.7 2.6h.6c.2 0 .4.2.4.4v1.6c0 .2-.2.4-.4.4h-.6c-.2 0-.4-.2-.4-.4V3c0-.2.2-.4.4-.4ZM1 7.2h.4c.4 0 .8.4.8.8v2.4c0 .4-.4.8-.8.8H1c-.4 0-.8-.4-.8-.8V8c0-.4.4-.8.8-.8Zm13.6 0h.4c.4 0 .8.4.8.8v2.4c0 .4-.4.8-.8.8h-.4c-.4 0-.8-.4-.8-.8V8c0-.4.4-.8.8-.8ZM5.6 4.6h4.8c1.7 0 3 1.3 3 3v4c0 1.7-1.3 3-3 3H5.6c-1.7 0-3-1.3-3-3v-4c0-1.7 1.3-3 3-3Zm.4 2.8a1.3 1.3 0 1 0 0 2.6 1.3 1.3 0 0 0 0-2.6Zm4 0a1.3 1.3 0 1 0 0 2.6 1.3 1.3 0 0 0 0-2.6Zm-3.75 4h3.5c.36 0 .65.29.65.65s-.29.65-.65.65h-3.5a.65.65 0 0 1 0-1.3Z" />
);

export const ROBOT = 'bondex.robot';

export default function Sym({ name, size, className }: { name: string; size: number; className?: string }) {
  if (name === ROBOT) {
    return (
      <svg className={className} viewBox="0 0 16 16" width={size * 1.18} height={size * 1.18} fill="currentColor" fillRule="evenodd" aria-hidden="true">
        {robot}
      </svg>
    );
  }
  const glyph = glyphs[name] ?? glyphs['app.fill'];
  const box = size * 1.2;
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      width={box}
      height={box}
      aria-hidden="true"
      fill={glyph.stroke ? 'none' : 'currentColor'}
      fillRule={glyph.evenOdd ? 'evenodd' : undefined}
      stroke={glyph.stroke ? 'currentColor' : undefined}
      strokeWidth={glyph.stroke}
      strokeLinecap={glyph.stroke ? 'round' : undefined}
      strokeLinejoin={glyph.stroke ? 'round' : undefined}
    >
      {glyph.body}
    </svg>
  );
}
