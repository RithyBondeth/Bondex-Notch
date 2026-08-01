import type { CSSProperties } from 'react';

/* Furniture for the mock desktop the demo panel sits on: a menu bar, a couple
   of desktop widgets and a dock. All of it is decorative — the panel is what
   the section is actually demonstrating — so it is quiet, dimmed, and hidden
   from assistive technology.

   No Apple marks anywhere. The shapes read as macOS; the branding does not
   pretend to be it. */

const MENUS = ['File', 'Edit', 'View', 'Go', 'Window', 'Help'];

export function Menubar() {
  return (
    <div className="menubar" aria-hidden="true">
      {/* No mark in the leading slot. Apple's guidelines do not permit the
          Apple logo in third-party marketing, and a lookalike standing in for
          it reads worse than nothing — the bold app name and the menu titles
          already say "macOS menu bar" on their own. */}
      <div className="menubar__group">
        <b>Finder</b>
        {MENUS.map((m) => (
          <span key={m}>{m}</span>
        ))}
      </div>
      <div className="menubar__group menubar__group--right">
        <span className="menubar__icon" data-icon="battery" />
        <span className="menubar__icon" data-icon="wifi" />
        <span className="menubar__icon" data-icon="search" />
        <span className="menubar__icon" data-icon="control" />
        <span className="menubar__clock">Thu 4:14 PM</span>
      </div>
    </div>
  );
}

/* Abstract gradient tiles rather than imitations of real app icons — at 34px
   the silhouette is all that reads, and inventing lookalikes of other
   companies' marks would be the wrong kind of realism. */
const DOCK_APPS: Array<{ id: string; from: string; to: string; running?: boolean }> = [
  { id: 'finder', from: '#5AC8FA', to: '#1D62D7', running: true },
  { id: 'mail', from: '#7FD2FF', to: '#2A7FE0' },
  { id: 'notes', from: '#FFD97A', to: '#E8A33D' },
  { id: 'music', from: '#FF7A8F', to: '#D63864', running: true },
  { id: 'photos', from: '#C3CFEA', to: '#8FA6D8' },
  { id: 'terminal', from: '#2B3550', to: '#0B0E18', running: true },
  { id: 'maps', from: '#7FE3B0', to: '#1E8A6A' },
  { id: 'settings', from: '#9AA6C4', to: '#5A6580' },
];

export function Dock() {
  return (
    <div className="dock" aria-hidden="true">
      {DOCK_APPS.map(({ id, from, to, running }) => (
        <span
          key={id}
          className={`dock__app${running ? ' is-running' : ''}`}
          style={{ '--from': from, '--to': to } as CSSProperties}
        />
      ))}
      <span className="dock__sep" />
      <span className="dock__app dock__app--trash" />
    </div>
  );
}

export function DesktopWidgets() {
  return (
    <div className="widgets" aria-hidden="true">
      <div className="widget widget--date">
        <span className="widget__label">Thursday</span>
        <span className="widget__date">14</span>
      </div>
      <div className="widget widget--weather">
        <span className="widget__label">Phnom Penh</span>
        <span className="widget__temp">31°</span>
        <span className="widget__sub">Humid · 33° / 26°</span>
      </div>
    </div>
  );
}
