import type { ReactNode } from 'react';

export type TabId = 'home' | 'music' | 'system' | 'live' | 'files' | 'activity' | 'shelf';

interface Tab {
  id: TabId;
  label: string;
  icon: ReactNode;
  /** In the app, only the selected chip reveals its label. */
  iconOnly?: boolean;
}

export const tabs: Tab[] = [
  {
    id: 'home',
    label: 'Home',
    icon: (
      <svg viewBox="0 0 16 16" aria-hidden="true">
        <rect x="2" y="2" width="5" height="5" rx="1.4" />
        <rect x="9" y="2" width="5" height="5" rx="1.4" />
        <rect x="2" y="9" width="5" height="5" rx="1.4" />
        <rect x="9" y="9" width="5" height="5" rx="1.4" />
      </svg>
    ),
  },
  {
    id: 'music',
    label: 'Music',
    iconOnly: true,
    icon: (
      <svg viewBox="0 0 16 16" aria-hidden="true">
        <path d="M13 2.6v7.7a2.2 2.2 0 1 1-1.4-2V5.3L6.6 6.5v5.6a2.2 2.2 0 1 1-1.4-2V4.4z" />
      </svg>
    ),
  },
  {
    id: 'system',
    label: 'System',
    iconOnly: true,
    icon: (
      <svg viewBox="0 0 16 16" aria-hidden="true">
        <path d="M2 11.5a6.2 6.2 0 1 1 12 0h-1.7a4.6 4.6 0 1 0-8.6 0zm5.4-.2 3.8-4.5.9.8-3.4 4.8a1.1 1.1 0 1 1-1.3-1.1z" />
      </svg>
    ),
  },
  {
    id: 'live',
    label: 'Live',
    iconOnly: true,
    icon: (
      <svg viewBox="0 0 16 16" aria-hidden="true">
        <path d="M1.5 8h2.4l1.3-3.4 2.1 7 1.8-5 1.2 2.5h4.2v1.4h-5l-.4-.2-1-2-2.2 6.1-2.1-7L4.8 9.4H1.5z" />
      </svg>
    ),
  },
  {
    id: 'files',
    label: 'Files',
    iconOnly: true,
    icon: (
      <svg viewBox="0 0 16 16" aria-hidden="true">
        <path d="M8 1.6a6.4 6.4 0 1 0 0 12.8A6.4 6.4 0 0 0 8 1.6zm.7 3.1v4l1.5-1.5.9.9L8 10.9 4.9 8.1l.9-.9 1.5 1.5v-4z" />
      </svg>
    ),
  },
  {
    id: 'activity',
    label: 'Activity',
    iconOnly: true,
    icon: (
      <svg viewBox="0 0 16 16" aria-hidden="true">
        <path d="M8 1.8a4 4 0 0 0-4 4v2.6L2.7 11h10.6L12 8.4V5.8a4 4 0 0 0-4-4zM6.4 12a1.6 1.6 0 0 0 3.2 0z" />
      </svg>
    ),
  },
  {
    id: 'shelf',
    label: 'Shelf',
    iconOnly: true,
    icon: (
      <svg viewBox="0 0 16 16" aria-hidden="true">
        <path d="M2 2.2h12v11.6H2zm1.5 1.5v6h2.1l.8 1.3h3.2l.8-1.3h2.1v-6z" />
      </svg>
    ),
  },
];

/* The sample data the panel shows. Fictional, but shaped exactly like what the
   app reports — the numbers are the point, so they use tabular figures. */

export default function PanelViews({
  active,
  ref,
}: {
  active: TabId;
  /** The demo measures this box to size the expanded panel to its content. */
  ref?: React.Ref<HTMLDivElement>;
}) {
  const view = (id: TabId) => `view${active === id ? ' is-active' : ''}`;

  return (
    <div className="panel__views" ref={ref}>
      <div className={view('home')} data-view="home">
        <div className="agent-card">
          <span className="agent-orb agent-orb--codex agent-card__orb" aria-hidden="true" />
          <span className="card__text">
            <b>Codex is working</b>
            <em>Refining the landing page</em>
          </span>
          <span className="agent-card__time">03:42</span>
        </div>
        <div className="live-card">
          <span className="live-card__icon" aria-hidden="true">↗</span>
          <span className="card__text">
            <b>Building release</b>
            <em>Running tests · 72%</em>
          </span>
          <span className="mini-progress" aria-hidden="true"><i /></span>
        </div>
        <div className="tiles">
          <div className="tile">
            <span className="ring" style={{ '--v': 0.23 } as React.CSSProperties}>
              <b>23%</b>
            </span>
            <em>CPU</em>
          </div>
          <div className="tile">
            <span
              className="ring ring--warn"
              style={{ '--v': 0.77 } as React.CSSProperties}
            >
              <b>77%</b>
            </span>
            <em>Memory</em>
          </div>
          <div className="tile">
            <span className="ring ring--ok" style={{ '--v': 1 } as React.CSSProperties}>
              <b>⚡</b>
            </span>
            <em>100%</em>
          </div>
          <div className="tile tile--net">
            <span className="net">
              <i>↓</i> 3.2 MB/s
            </span>
            <span className="net net--dim">
              <i>↑</i> 118 KB/s
            </span>
            <em>Network</em>
          </div>
        </div>
      </div>

      <div className={view('system')} data-view="system">
        <div className="tiles tiles--standalone">
          <div className="tile">
            <span className="ring" style={{ '--v': 0.23 } as React.CSSProperties}><b>23%</b></span>
            <em>CPU</em>
          </div>
          <div className="tile">
            <span className="ring ring--warn" style={{ '--v': 0.77 } as React.CSSProperties}><b>77%</b></span>
            <em>Memory</em>
          </div>
          <div className="tile">
            <span className="ring ring--ok" style={{ '--v': 1 } as React.CSSProperties}><b>⚡</b></span>
            <em>AC power</em>
          </div>
          <div className="tile tile--net">
            <span className="net"><i>↓</i> 3.2 MB/s</span>
            <span className="net net--dim"><i>↑</i> 118 KB/s</span>
            <em>Network</em>
          </div>
        </div>
      </div>

      <div className={view('live')} data-view="live">
        <div className="mock-list__head"><span>Live activities</span><em>1 running</em></div>
        <div className="row mock-live-row">
          <span className="mock-progress" style={{ '--v': 0.72 } as React.CSSProperties}><i>↗</i></span>
          <span className="row__text"><b>Building release</b><em>Running tests</em></span>
          <strong>72%</strong>
        </div>
        <div className="row mock-live-row mock-live-row--quiet">
          <span className="mock-live-pulse">⌁</span>
          <span className="row__text"><b>Watching preview</b><em>localhost:4173</em></span>
          <strong>Live</strong>
        </div>
      </div>

      <div className={view('music')} data-view="music">
        <div className="player">
          <span className="player__art" aria-hidden="true" />
          <div className="player__meta">
            <b>Weightless</b>
            <em>Marconi Union — Ambient Transmissions</em>
            <span className="bar">
              <i style={{ width: '38%' }} />
            </span>
            <span className="times">
              <span>3:12</span>
              <span>8:09</span>
            </span>
          </div>
        </div>
      </div>

      <div className={view('files')} data-view="files">
        <div className="row">
          <span className="row__icon row__icon--dl" aria-hidden="true" />
          <span className="row__text">
            <b>Xcode_26.xip</b>
            <em>4.1 GB · 22.4 MB/s</em>
          </span>
          <span className="spinner" aria-hidden="true" />
        </div>
        <div className="row">
          <span className="row__icon" aria-hidden="true" />
          <span className="row__text">
            <b>design-review.sketch</b>
            <em>184 MB</em>
          </span>
        </div>
      </div>

      <div className={view('activity')} data-view="activity">
        <div className="row row--slim">
          <span className="dot dot--azure" aria-hidden="true" />
          <span className="row__text">
            <b>Xcode_26.xip</b>
            <em>Download complete · 7.4 GB</em>
          </span>
          <span className="row__time">4:14 PM</span>
        </div>
        <div className="row row--slim">
          <span className="dot dot--mauve" aria-hidden="true" />
          <span className="row__text">
            <b>Weightless</b>
            <em>Marconi Union</em>
          </span>
          <span className="row__time">4:11 PM</span>
        </div>
        <div className="row row--slim">
          <span className="dot dot--cobalt" aria-hidden="true" />
          <span className="row__text">
            <b>Low Battery</b>
            <em>14% remaining</em>
          </span>
          <span className="row__time">3:58 PM</span>
        </div>
      </div>

      <div className={view('shelf')} data-view="shelf">
        <div className="mock-list__head"><span>3 items</span><em>Drag out to use</em></div>
        <div className="mock-shelf">
          <div><span className="mock-file mock-file--pdf">PDF</span><em>Launch brief.pdf</em></div>
          <div><span className="mock-file mock-file--image">PNG</span><em>Hero artwork.png</em></div>
          <div><span className="mock-file mock-file--code">TSX</span><em>NotchDemo.tsx</em></div>
          <div className="mock-shelf__drop"><b>＋</b><em>Drop files here</em></div>
        </div>
      </div>
    </div>
  );
}
