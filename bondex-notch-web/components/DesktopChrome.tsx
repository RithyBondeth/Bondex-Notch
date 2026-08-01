import Image from 'next/image';

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

/* The demo is intentionally a recognisable Mac desktop, so the Dock uses
   artwork from the corresponding apps installed with macOS. */
const DOCK_APPS: Array<{ id: string; icon: string; running?: boolean }> = [
  { id: 'finder', icon: '/macos-icons/finder.png', running: true },
  { id: 'safari', icon: '/macos-icons/safari.png' },
  { id: 'mail', icon: '/macos-icons/mail.png' },
  { id: 'notes', icon: '/macos-icons/notes.png' },
  { id: 'music', icon: '/macos-icons/music.png', running: true },
  { id: 'photos', icon: '/macos-icons/photos.png' },
  { id: 'terminal', icon: '/macos-icons/terminal.png', running: true },
  { id: 'settings', icon: '/macos-icons/settings.png' },
];

export function Dock() {
  return (
    <div className="dock" aria-hidden="true">
      {DOCK_APPS.map(({ id, icon, running }) => (
        <span key={id} className={`dock__app${running ? ' is-running' : ''}`}>
          <Image src={icon} alt="" width={68} height={68} />
        </span>
      ))}
      <span className="dock__sep" />
      <span className="dock__app dock__app--trash">
        <Image src="/macos-icons/trash.png" alt="" width={68} height={68} />
      </span>
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
