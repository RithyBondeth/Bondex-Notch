'use client';

import { useEffect, useRef, useState } from 'react';
import { DesktopWidgets, Dock, Menubar } from './DesktopChrome';
import NotchSurface, { type SurfaceState, peekFor } from './panel/NotchSurface';
import useFitZoom from './panel/useFitZoom';
import { useDemo } from './panel/useDemo';

/* NotchViewModel's timing: a short dwell before opening, so a pointer on its
   way to the menu bar does not fire the panel, and a grace period before
   closing. */
const HOVER_DELAY = 180;
const CLOSE_DELAY = 300;

/**
 * The hero: the real panel on a mock desktop, driven by the app's state
 * machine. Hover to open, click to pin, Escape or × to close. While closed
 * it rests in whatever the app would show — here, Claude working.
 */
export default function NotchDemo() {
  const { setRoot, ...demo } = useDemo({ agents: ['claude'], build: false, meeting: false });
  const [state, setState] = useState<SurfaceState>('peek');
  const [interacted, setInteracted] = useState(false);
  const pinned = useRef(false);
  const openTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
  const closeTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
  const screen = useRef<HTMLDivElement>(null);
  // Room for the widest profile panel and its fillets, with a margin.
  const zoom = useFitZoom(screen, 600);

  /** `idleState`: the peek while something is live, otherwise collapsed. */
  const idle: SurfaceState = peekFor(demo) ? 'peek' : 'collapsed';

  const expand = () => {
    clearTimeout(openTimer.current);
    clearTimeout(closeTimer.current);
    setState('expanded');
    setInteracted(true);
  };

  const collapse = () => {
    clearTimeout(openTimer.current);
    clearTimeout(closeTimer.current);
    pinned.current = false;
    demo.closePalette();
    setState('collapsed');
  };

  useEffect(() => () => {
    clearTimeout(openTimer.current);
    clearTimeout(closeTimer.current);
  }, []);

  const shown: SurfaceState = state === 'expanded' ? 'expanded' : idle;

  return (
    <div className="stage" ref={setRoot}>
      <div className="stage__screen" ref={screen}>
        <Menubar />
        <DesktopWidgets />

        <div className="stage__notch" style={{ zoom }}>
          <NotchSurface
            demo={demo}
            state={shown}
            role="region"
            aria-label="Interactive demo of the Bondex Notch panel"
            onClose={collapse}
            onMouseEnter={() => {
              clearTimeout(closeTimer.current);
              if (shown !== 'expanded') openTimer.current = setTimeout(expand, HOVER_DELAY);
            }}
            onMouseLeave={() => {
              clearTimeout(openTimer.current);
              if (shown === 'expanded' && !pinned.current) {
                closeTimer.current = setTimeout(collapse, CLOSE_DELAY);
              }
            }}
            onFocus={() => {
              if (shown !== 'expanded') expand();
            }}
            onClick={() => {
              // Opens the notch, or latches the open panel. Never closes it.
              pinned.current = true;
              if (shown !== 'expanded') expand();
            }}
            onKeyDown={(event) => {
              if (event.key !== 'Escape' || shown !== 'expanded') return;
              event.preventDefault();
              if (demo.paletteOpen) demo.closePalette();
              else collapse();
            }}
            onDropFiles={(names) => {
              demo.addToShelf(names);
              demo.setTab('shelf');
              pinned.current = true;
              expand();
            }}
          />
        </div>

        <p className={`stage__hint${interacted ? ' is-hidden' : ''}`}>Hover the notch</p>

        <Dock />
      </div>
    </div>
  );
}
