'use client';

import { type CSSProperties, useCallback, useEffect, useRef, useState } from 'react';
import { DesktopWidgets, Dock, Menubar } from './DesktopChrome';
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
  const [expandedHeight, setExpandedHeight] = useState<number | null>(null);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [commandQuery, setCommandQuery] = useState('');

  // Mirrors the app: the panel falls back to a peek while "media is playing",
  // and only fully closes when nothing is live.
  const idleState = useRef<State>('peek');
  const pinned = useRef(false);
  const interactedRef = useRef(false);
  const closeTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
  const viewsRef = useRef<HTMLDivElement>(null);

  const expand = useCallback(() => {
    clearTimeout(closeTimer.current);
    setState('expanded');
    if (!interactedRef.current) {
      interactedRef.current = true;
      setInteracted(true);
    }
  }, []);

  const commands: Array<{ id: string; icon: string; title: string; detail: string; tab: TabId }> = [
    { id: 'capture', icon: '✎', title: 'Quick Capture', detail: 'Save a note or link', tab: 'capture' },
    { id: 'music', icon: '♪', title: 'Music player', detail: 'Open Spotify playback', tab: 'music' },
    { id: 'system', icon: '◴', title: 'System monitor', detail: 'View CPU, memory and battery', tab: 'system' },
    { id: 'clipboard', icon: '▤', title: 'Clipboard history', detail: 'Find something copied', tab: 'clipboard' },
    { id: 'files', icon: '↓', title: 'Downloads', detail: 'View recent transfers', tab: 'files' },
    { id: 'activity', icon: '●', title: 'Recent activity', detail: 'Review completed events', tab: 'activity' },
  ];
  const visibleCommands = commands.filter((command) =>
    `${command.title} ${command.detail}`.toLowerCase().includes(commandQuery.trim().toLowerCase()),
  );

  const runCommand = (target: TabId) => {
    pinned.current = true;
    setTab(target);
    setPaletteOpen(false);
    setCommandQuery('');
  };

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

  /* The expanded panel is as tall as whichever view is showing. Hard-coding a
     height means the tallest view spills onto the wallpaper and the shortest
     leaves a void, so measure instead: the views box sits below the tabs and
     the divider, and `offsetTop` already accounts for both plus the panel's
     top padding. A ResizeObserver catches the tab switch and any reflow the
     webfonts cause when they land. */
  useEffect(() => {
    const views = viewsRef.current;
    const panel = views?.parentElement;
    if (!views || !panel) return;

    const measure = () => {
      const padBottom = parseFloat(getComputedStyle(panel).paddingBottom) || 0;
      setExpandedHeight(Math.ceil(views.offsetTop + views.offsetHeight + padBottom));
    };

    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(views);
    return () => observer.disconnect();
  }, [paletteOpen, tab]);

  return (
    <div className="stage">
      <div className="stage__screen">
        <Menubar />
        <DesktopWidgets />

        <div
          className="notch"
          data-state={state}
          role="region"
          aria-label="Interactive demo of the Bondex Notch panel"
          onMouseEnter={expand}
          onMouseLeave={() => {
            if (!pinned.current) scheduleClose();
          }}
          onFocus={expand}
          onBlur={() => {
            if (!pinned.current) scheduleClose();
          }}
          onClick={(event) => {
            // Tabs and the command palette handle their own clicks.
            if ((event.target as HTMLElement).closest('.chip, .panel__action, .panel-command-host')) return;
            togglePin();
          }}
          onKeyDown={(event) => {
            if (event.key !== 'Escape') return;

            event.preventDefault();
            if (paletteOpen) {
              setPaletteOpen(false);
              setCommandQuery('');
            } else {
              pinned.current = false;
              setState(idleState.current);
            }
          }}
        >
          <div
            className="notch__body"
            /* Only while expanded — collapsed and peek keep their own heights
               from the stylesheet. */
            style={
              state === 'expanded' && expandedHeight
                ? ({ '--h': `${expandedHeight}px` } as CSSProperties)
                : undefined
            }
          >
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
                <div className="panel__tab-group">
                  {tabs.map(({ id, label, icon }) => (
                    <button
                      key={id}
                      className={`chip${tab === id ? ' is-active' : ''}`}
                      role="tab"
                      aria-selected={tab === id}
                      aria-label={tab === id ? undefined : label}
                      onClick={(event) => {
                        event.stopPropagation();
                        pinned.current = true;
                        setTab(id);
                        setPaletteOpen(false);
                      }}
                      >
                      {icon}
                      {tab === id && <span>{label}</span>}
                    </button>
                  ))}
                </div>
                <button
                  type="button"
                  className="panel__action"
                  aria-label="Search actions"
                  aria-expanded={paletteOpen}
                  onClick={(event) => {
                    event.stopPropagation();
                    pinned.current = true;
                    setCommandQuery('');
                    setPaletteOpen(true);
                  }}
                >
                  ⌕
                </button>
                <button
                  type="button"
                  className="panel__close"
                  aria-label="Collapse panel"
                  onClick={(event) => {
                    event.stopPropagation();
                    pinned.current = false;
                    setPaletteOpen(false);
                    setState('collapsed');
                  }}
                >
                  ×
                </button>
              </div>

              <div className="panel__divider" aria-hidden="true" />
              {paletteOpen ? (
                <div className="panel-command-host" ref={viewsRef} onClick={(event) => event.stopPropagation()}>
                  <div className="real-command-surface real-command-surface--embedded" role="dialog" aria-label="Search Bondex actions">
                    <div className="real-command-search-row">
                      <span aria-hidden="true">⌕</span>
                      <input
                        autoFocus
                        value={commandQuery}
                        onChange={(event) => setCommandQuery(event.target.value)}
                        onKeyDown={(event) => {
                          event.stopPropagation();
                          if (event.key === 'Escape') {
                            setPaletteOpen(false);
                            setCommandQuery('');
                          } else if (event.key === 'Enter') {
                            const first = visibleCommands[0];
                            if (first) runCommand(first.tab);
                          }
                        }}
                        placeholder="Search actions…"
                        aria-label="Search actions"
                      />
                      <kbd>esc</kbd>
                      <button type="button" aria-label="Close action search" onClick={() => setPaletteOpen(false)}>×</button>
                    </div>
                    <div className="real-command-results" role="listbox" aria-label="Available actions">
                      {visibleCommands.map((command, index) => (
                        <button
                          type="button"
                          role="option"
                          aria-selected={index === 0}
                          className={index === 0 ? 'is-selected' : ''}
                          onClick={() => runCommand(command.tab)}
                          key={command.id}
                        >
                          <i>{command.icon}</i>
                          <span><b>{command.title}</b><small>{command.detail}</small></span>
                          <em>Open</em>
                          {index === 0 && <kbd>↵</kbd>}
                        </button>
                      ))}
                      {visibleCommands.length === 0 && (
                        <div className="real-command-empty"><b>No matching actions</b><small>Try “music”, “system”, or “clipboard”.</small></div>
                      )}
                    </div>
                    <div className="real-command-footer"><span>Type to filter</span><span>↵ &nbsp; Open</span><button type="button" onClick={() => setPaletteOpen(false)}>Close</button></div>
                  </div>
                </div>
              ) : (
                <PanelViews active={tab} ref={viewsRef} />
              )}
            </div>
          </div>
        </div>

        <p className={`stage__hint${interacted ? ' is-hidden' : ''}`}>
          Hover the notch
        </p>

        <Dock />
      </div>
    </div>
  );
}
