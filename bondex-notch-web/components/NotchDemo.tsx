'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import PanelViews, { type TabId, tabs } from './PanelViews';

type State = 'collapsed' | 'peek' | 'expanded';

const CLOSE_DELAY = 260;
const AMBIENT_INTERVAL = 3200;

/**
 * A working replica of the panel, driven by the same state machine as the app:
 * collapsed → peek → expanded. Hover to open, click to pin, Escape to close.
 *
 * `idleState` and `pinned` are refs rather than state: the ambient loop and the
 * close timer both read them from inside callbacks that outlive a render, and
 * neither should trigger one on its own.
 */
export default function NotchDemo() {
  const [state, setState] = useState<State>('collapsed');
  const [tab, setTab] = useState<TabId>('home');
  const [interacted, setInteracted] = useState(false);

  // Mirrors the app: the panel falls back to a peek while "media is playing",
  // and only fully closes when nothing is live.
  const idleState = useRef<State>('peek');
  const pinned = useRef(false);
  const interactedRef = useRef(false);
  const closeTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

  const expand = useCallback(() => {
    clearTimeout(closeTimer.current);
    setState('expanded');
    if (!interactedRef.current) {
      interactedRef.current = true;
      setInteracted(true);
    }
  }, []);

  const scheduleClose = useCallback(() => {
    clearTimeout(closeTimer.current);
    closeTimer.current = setTimeout(() => {
      if (!pinned.current) setState(idleState.current);
    }, CLOSE_DELAY);
  }, []);

  const togglePin = useCallback(() => {
    if (pinned.current) {
      pinned.current = false;
      setState(idleState.current);
    } else {
      pinned.current = true;
      expand();
    }
  }, [expand]);

  /* Before anyone touches it, cycle collapsed → peek so the shape reads as a
     live product rather than a screenshot. Stops for good on first
     interaction, and never runs under reduced motion. */
  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    let phase = 0;
    const ambient = setInterval(() => {
      if (interactedRef.current) {
        clearInterval(ambient);
        return;
      }
      phase = (phase + 1) % 2;
      idleState.current = phase === 0 ? 'collapsed' : 'peek';
      setState(idleState.current);
    }, AMBIENT_INTERVAL);

    return () => clearInterval(ambient);
  }, []);

  useEffect(() => {
    setState(idleState.current);
    return () => clearTimeout(closeTimer.current);
  }, []);

  return (
    <div className="stage">
      <div className="stage__screen">
        <div className="stage__menubar" aria-hidden="true">
          <span className="stage__menubar-left" />
          <span className="stage__menubar-right" />
        </div>

        <div
          className="notch"
          data-state={state}
          tabIndex={0}
          role="button"
          aria-expanded={state === 'expanded'}
          aria-label="Interactive demo of the Bondex Notch panel. Activate to expand."
          onMouseEnter={expand}
          onMouseLeave={() => {
            if (!pinned.current) scheduleClose();
          }}
          onFocus={expand}
          onBlur={() => {
            if (!pinned.current) scheduleClose();
          }}
          onClick={(event) => {
            // Tab chips handle their own clicks.
            if ((event.target as HTMLElement).closest('.chip')) return;
            togglePin();
          }}
          onKeyDown={(event) => {
            if (event.key === 'Enter' || event.key === ' ') {
              event.preventDefault();
              togglePin();
            } else if (event.key === 'Escape') {
              pinned.current = false;
              setState(idleState.current);
            }
          }}
        >
          <div className="notch__body">
            <div className="notch__peek">
              <span className="peek__art" aria-hidden="true" />
              <span className="notch__gap" aria-hidden="true" />
              <span className="peek__bars" aria-hidden="true">
                <i />
                <i />
                <i />
                <i />
              </span>
            </div>

            <div className="notch__panel">
              <div className="panel__tabs" role="tablist" aria-label="Demo widgets">
                {tabs.map(({ id, label, icon, iconOnly }) => (
                  <button
                    key={id}
                    className={`chip${tab === id ? ' is-active' : ''}`}
                    role="tab"
                    aria-selected={tab === id}
                    aria-label={iconOnly ? label : undefined}
                    onClick={(event) => {
                      event.stopPropagation();
                      pinned.current = true;
                      setTab(id);
                    }}
                  >
                    {icon}
                    {!iconOnly && <span>{label}</span>}
                  </button>
                ))}
              </div>

              <div className="panel__divider" aria-hidden="true" />
              <PanelViews active={tab} />
            </div>
          </div>
        </div>

        <p className={`stage__hint${interacted ? ' is-hidden' : ''}`}>
          Hover the notch
        </p>
      </div>
    </div>
  );
}
