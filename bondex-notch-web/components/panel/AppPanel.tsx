'use client';

import Image from 'next/image';
import { type CSSProperties, Fragment, type ReactNode, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { AgentOrb, PixelMark } from './marks';
import {
  type AgentId, type Provider, type TabId,
  CUSTOM_ACTIONS, PALETTE_SHORTCUT, PROVIDERS, RANGES, TABS, USAGE_BREAKDOWNS, USAGE_PROVIDERS, USAGE_SESSIONS,
  actionSubtitle, actionSymbol, agentName, agentTint, agoString, clockString, countdownString, liveSession,
  timeOfDay, tokenString, usageSummaries, usdString,
} from './model';
import Sym from './Symbol';
import { type Demo, type NotchEvent, EVENT_KINDS, byteString, captureDetail, clipboardDetail, clipboardSymbol, isLink } from './useDemo';

/* The expanded panel, as ExpandedView lays it out: the controls in the band
   beside the hardware notch, the tab strip on a row of its own, a hairline,
   and one widget measured from its content. Sizes are the app's points, one
   CSS pixel each; the type scale and radii are Theme's. */

export const NOTCH_WIDTH = 185;
const SECONDARY = 'var(--ap-secondary)';

const css = (values: Record<string, string | number>) => values as CSSProperties;

/* ── Shared controls ─────────────────────────────────────── */

/** NotchButton: a circle `size + 15` across, prominent ones filled with the tint. */
function NotchButton({
  symbol, size, label, onClick, prominent = false, tint, disabled = false, className,
}: {
  symbol: string; size: number; label: string; onClick?: () => void;
  prominent?: boolean; tint?: string; disabled?: boolean; className?: string;
}) {
  return (
    <button
      type="button"
      className={`ap-button${prominent ? ' is-prominent' : ''}${className ? ` ${className}` : ''}`}
      style={css({ '--size': `${size + 15}px`, ...(tint ? { '--tint': tint } : {}) })}
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={(event) => {
        event.stopPropagation();
        onClick?.();
      }}
    >
      <Sym name={symbol} size={size} />
    </button>
  );
}

function TextButton({ children, onClick, warning = false }: { children: ReactNode; onClick: () => void; warning?: boolean }) {
  return (
    <button type="button" className={`ap-text-button${warning ? ' is-warning' : ''}`} onClick={(event) => { event.stopPropagation(); onClick(); }}>
      {children}
    </button>
  );
}

function ListHeader({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="ap-list-header">
      <span>{title}</span>
      {children && <span className="ap-list-header__actions">{children}</span>}
    </div>
  );
}

function EmptyState({ symbol, title, subtitle }: { symbol: string; title: string; subtitle?: string }) {
  return (
    <div className="ap-empty">
      <Sym name={symbol} size={20} />
      <b>{title}</b>
      {subtitle && <small>{subtitle}</small>}
    </div>
  );
}

function Ring({ value, tint, line, size }: { value: number; tint: string; line: number; size: number }) {
  const r = (size - line) / 2;
  const c = 2 * Math.PI * r;
  const v = Math.min(Math.max(value, 0), 1);
  return (
    <svg className="ap-ring" width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
      <circle cx={size / 2} cy={size / 2} r={r} strokeWidth={line} stroke="rgba(255,255,255,.12)" />
      <circle cx={size / 2} cy={size / 2} r={r} strokeWidth={line} stroke={tint} strokeDasharray={`${c * v} ${c}`} strokeLinecap={v > 0 ? 'round' : 'butt'} transform={`rotate(-90 ${size / 2} ${size / 2})`} />
    </svg>
  );
}

function Meter({ value, tint, height }: { value: number; tint: string; height: number }) {
  const v = Math.min(Math.max(value, 0), 1);
  return (
    <span className="ap-meter" style={{ height }}>
      <i style={{ width: `max(${v * 100}%, ${v > 0 ? 3 : 0}px)`, background: tint }} />
    </span>
  );
}

/** AudioBars: four bars on durations that share no common multiple. */
export function AudioBars({ playing, tint }: { playing: boolean; tint: string }) {
  return (
    <span className={`ap-bars${playing ? ' is-playing' : ''}`} style={css({ '--tint': tint })} aria-hidden="true">
      <i /><i /><i /><i />
    </span>
  );
}

/** ArtworkView: a 1pt hairline over the art, clipped to its corners. */
function Artwork({ src, width, height, radius }: { src: string; width: number; height: number; radius: number }) {
  return (
    <span className="ap-artwork" style={{ width, height, borderRadius: radius }}>
      <Image src={src} alt="" width={width * 2} height={height * 2} />
    </span>
  );
}

/* ── The panel ───────────────────────────────────────────── */

export default function AppPanel({ demo, onClose }: { demo: Demo; onClose: () => void }) {
  const wing = (demo.panelWidth - NOTCH_WIDTH) / 2 - 14;
  const strip = useRef<HTMLDivElement>(null);
  const pill = useRef<HTMLElement>(null);

  /* One selection pill, handed from chip to chip so it slides to the new tab
     (the app's matchedGeometryEffect). The first placement does not animate. */
  useLayoutEffect(() => {
    const chip = strip.current?.querySelector<HTMLElement>(`[data-tab="${demo.tab}"]`);
    const indicator = pill.current;
    if (!chip || !indicator) return;
    const place = () => {
      indicator.style.transform = `translateX(${chip.offsetLeft}px)`;
      indicator.style.width = `${chip.offsetWidth}px`;
    };
    if (!indicator.dataset.placed) {
      indicator.style.transition = 'none';
      place();
      void indicator.offsetWidth;
      indicator.style.transition = '';
      indicator.dataset.placed = 'true';
    } else {
      place();
    }
  }, [demo.tab, demo.tabs, demo.paletteOpen]);

  return (
    <div className="ap" style={css({ '--accent': demo.accentHex, width: demo.panelWidth })}>
      {/* The band either side of the hardware notch. */}
      <div className="ap-band" style={css({ '--wing': `${wing}px`, '--notch': `${NOTCH_WIDTH}px` })}>
        <div className="ap-band__wing">
          <NotchButton symbol="gearshape.fill" size={9} label="Settings" tint={SECONDARY} />
          {demo.activeProfile && (
            <span className="ap-profile-mark" title={`${demo.activeProfile.name} profile active`} aria-label={`${demo.activeProfile.name} profile active`}>
              <Sym name={demo.activeProfile.symbol} size={9} />
            </span>
          )}
        </div>
        <span aria-hidden="true" />
        <div className="ap-band__wing ap-band__wing--trailing">
          <NotchButton
            symbol="magnifyingglass"
            size={9}
            label={demo.paletteOpen ? 'Close Command Palette' : `Command Palette (${PALETTE_SHORTCUT})`}
            tint={demo.paletteOpen ? demo.accentHex : SECONDARY}
            onClick={() => (demo.paletteOpen ? demo.closePalette() : demo.openPalette())}
          />
          <NotchButton symbol="xmark" size={9} label="Close" tint={SECONDARY} onClick={onClose} />
        </div>
      </div>

      <div className="ap-body">
        {demo.paletteOpen ? (
          <Palette demo={demo} />
        ) : (
          <>
            <div className="ap-tabs" role="tablist" aria-label="Widgets" ref={strip}>
              <i className="ap-tabs__pill" ref={pill} aria-hidden="true" />
              {demo.tabs.map((item) => (
                <button
                  key={item}
                  type="button"
                  role="tab"
                  data-tab={item}
                  className={`ap-tab${demo.tab === item ? ' is-selected' : ''}`}
                  aria-selected={demo.tab === item}
                  aria-label={TABS[item].title}
                  title={TABS[item].title}
                  onClick={(event) => {
                    event.stopPropagation();
                    demo.setTab(item);
                  }}
                >
                  <Sym name={TABS[item].symbol} size={9} />
                  {demo.tab === item && <span>{TABS[item].title}</span>}
                </button>
              ))}
            </div>
            <div className="ap-divider" aria-hidden="true" />
            <div
              key={demo.tab}
              className={`ap-widget${CAPPED.has(demo.tab) ? ' is-capped' : ''}`}
              data-from={demo.tabAdvances ? 'trailing' : 'leading'}
              role="tabpanel"
            >
              <Widget demo={demo} tab={demo.tab} />
            </div>
          </>
        )}
      </div>
    </div>
  );
}

/** `NotchTab.widgetHeight`: list tabs stop at 132pt and scroll. */
const CAPPED = new Set<TabId>(['capture', 'shortcuts', 'live', 'files', 'activity', 'clipboard', 'shelf']);

function Widget({ demo, tab }: { demo: Demo; tab: TabId }) {
  switch (tab) {
    case 'home': return <HomeWidget demo={demo} />;
    case 'agents': return <AgentsWidget demo={demo} />;
    case 'capture': return <CaptureWidget demo={demo} />;
    case 'shortcuts': return <ShortcutsWidget demo={demo} />;
    case 'music': return <MusicWidget demo={demo} />;
    case 'system': return <SystemWidget demo={demo} />;
    case 'live': return <LiveWidget demo={demo} />;
    case 'files': return <FilesWidget demo={demo} />;
    case 'activity': return <ActivityWidget demo={demo} />;
    case 'clipboard': return <ClipboardWidget demo={demo} />;
    case 'shelf': return <ShelfWidget demo={demo} />;
  }
}

/* ── Home · HomeWidget ───────────────────────────────────── */

function HomeWidget({ demo }: { demo: Demo }) {
  const { focus, accentHex: accent } = demo;
  const showsMedia = demo.isEnabled('music');
  const showsLive = demo.isEnabled('live') && demo.build !== null;
  const showsAgents = demo.agents.length > 0;
  const visible = demo.agents.slice(0, 3);
  const overflow = demo.agents.length - visible.length;

  return (
    <div className="ap-stack">
      {focus && (
        <div className="ap-card ap-card--compact ap-row-card">
          <span className="ap-focus-ring">
            <Ring value={1 - focus.remaining / (25 * 60)} tint={accent} line={2.5} size={30} />
            <Sym name="timer" size={10} />
          </span>
          <span className="ap-text">
            <b className="ap-body-strong">Focus session</b>
            <small className="ap-footnote ap-digits">{clockString(focus.remaining)}</small>
          </span>
          <NotchButton symbol={focus.running ? 'pause.fill' : 'play.fill'} size={10} prominent tint={accent} label={focus.running ? 'Pause focus timer' : 'Resume focus timer'} onClick={demo.toggleFocusRunning} />
          <NotchButton symbol="xmark" size={9} label="Cancel focus timer" tint={SECONDARY} onClick={demo.cancelFocus} />
        </div>
      )}

      {demo.meeting && demo.meetingIn > 0 && (
        <div className="ap-card ap-card--compact ap-row-card">
          <span className="ap-meeting-icon"><Sym name="calendar.badge.clock" size={13} /></span>
          <span className="ap-text">
            <b className="ap-body-strong">Product design review</b>
            <small className="ap-footnote">In {Math.ceil(demo.meetingIn / 60)} min</small>
          </span>
          <button type="button" className="ap-system-button" onClick={(event) => event.stopPropagation()}>Join</button>
        </div>
      )}

      {showsLive && demo.build && (
        <div className="ap-card ap-card--compact">
          <LiveRow title="Building release" subtitle="Running tests" progress={demo.build.progress} accent={accent} />
        </div>
      )}

      {showsAgents && (
        <div className="ap-card ap-card--compact ap-agents">
          {visible.map((agent, index) => {
            const session = liveSession(agent.id, demo.tick);
            return (
              <Fragment key={agent.id}>
              {index > 0 && <i className="ap-hairline" aria-hidden="true" />}
              <div className="ap-agent">
                <AgentOrb id={agent.id} size={26} attention={agent.attention} />
                <span className="ap-text">
                  <span className="ap-agent__title">
                    <b>{agentName(agent.id)}</b>
                    {session && <em>{session.project}</em>}
                    {session && <strong style={css({ '--tint': agentTint(agent.id) })}>{session.model}</strong>}
                  </span>
                  <small className={agent.attention ? 'is-attention' : undefined}>{demo.agentStatus(agent)}</small>
                </span>
                {agent.attention ? (
                  <span className="ap-needs-you">Needs you</span>
                ) : (
                  <time className="ap-agent__clock" style={{ color: agentTint(agent.id) }}>{clockString(demo.tick - agent.since)}</time>
                )}
              </div>
              </Fragment>
            );
          })}
          {overflow > 0 && <small className="ap-overflow">+{overflow} more working</small>}
        </div>
      )}

      {showsMedia && (
        <div className="ap-card ap-home-media">
          <div className="ap-home-media__row">
            <Artwork src={demo.track.artwork} width={44} height={44} radius={8} />
            <span className="ap-text ap-home-media__text">
              <b>{demo.track.title}</b>
              <small>{demo.track.artist}<i aria-hidden="true" />Spotify</small>
            </span>
            <span className="ap-transport">
              <NotchButton symbol="backward.fill" size={10} label="Previous" onClick={demo.previousTrack} />
              <NotchButton symbol={demo.music.playing ? 'pause.fill' : 'play.fill'} size={12} prominent tint={accent} label={demo.music.playing ? 'Pause' : 'Play'} onClick={demo.playPause} />
              <NotchButton symbol="forward.fill" size={10} label="Next" onClick={demo.nextTrack} />
            </span>
          </div>
          <Meter value={demo.music.position / demo.track.duration} tint={accent} height={2} />
        </div>
      )}

      {!focus && (
        <div>
          <button type="button" className="ap-focus-chip" title="Start a 25-minute focus session" onClick={(event) => { event.stopPropagation(); demo.startFocus(); }}>
            <Sym name="timer" size={9} />
            <b>Focus</b>
            <span>25 min</span>
          </button>
        </div>
      )}
    </div>
  );
}

function LiveRow({ title, subtitle, progress, accent }: { title: string; subtitle: string; progress: number; accent: string }) {
  return (
    <div className="ap-live">
      <span className="ap-live__icon">
        <Ring value={progress} tint={accent} line={2.5} size={21} />
      </span>
      <span className="ap-text">
        <b className="ap-body-strong">{title}</b>
        <small className="ap-caption ap-secondary">{subtitle}</small>
      </span>
      <strong className="ap-live__value">{Math.floor(progress * 100)}%</strong>
    </div>
  );
}

/* ── Agents · AgentUsageWidget ───────────────────────────── */

function CardHeader({ title, mark, symbol, detail, children }: { title: string; mark?: Provider; symbol?: string; detail?: string; children?: ReactNode }) {
  return (
    <div className="ap-card-header">
      {mark ? <PixelMark id={mark} width={15} /> : symbol && <span className="ap-card-header__icon"><Sym name={symbol} size={11} /></span>}
      <b>{title}</b>
      {detail && <em>{detail}</em>}
      <span className="ap-spacer" />
      {children}
    </div>
  );
}

function ChipPicker<T extends string>({ options, value, onChange, label, size = 9.5 }: { options: Array<{ id: T; title: string }>; value: T; onChange: (value: T) => void; label: string; size?: number }) {
  return (
    <span className="ap-chips" role="group" aria-label={label} style={{ fontSize: size }}>
      {options.map((option) => (
        <button
          key={option.id}
          type="button"
          aria-pressed={value === option.id}
          className={value === option.id ? 'is-selected' : undefined}
          onClick={(event) => {
            event.stopPropagation();
            onChange(option.id);
          }}
        >
          {option.title}
        </button>
      ))}
    </span>
  );
}

type Breakdown = 'trend' | 'projects' | 'models';
const BREAKDOWNS: Array<{ id: Breakdown; title: string; symbol: string }> = [
  { id: 'trend', title: 'Trend', symbol: 'chart.bar.fill' },
  { id: 'projects', title: 'Projects', symbol: 'folder.fill' },
  { id: 'models', title: 'Models', symbol: 'cpu' },
];

function AgentsWidget({ demo }: { demo: Demo }) {
  // Not persisted: each opening starts on the trend.
  const [breakdown, setBreakdown] = useState<Breakdown>('trend');
  const { loadedAt, tick } = demo;

  if (!loadedAt) {
    return <div className="ap-loading"><span className="ap-spinner" />Reading agent logs…</div>;
  }

  const summaries = usageSummaries(loadedAt);
  const summary = summaries[demo.usageRange];
  const range = RANGES.find((item) => item.id === demo.usageRange)!;
  const total = { tokens: summary.claude.tokens + summary.codex.tokens, cost: summary.claude.cost + summary.codex.cost };
  const scale = total.tokens / (summaries.today.claude.tokens + summaries.today.codex.tokens);

  /* SessionsCard: live status from the hooks laid over the newest session of
     each working agent; an agent with no logs still gets a row. */
  const working = demo.agents;
  const claimed = new Set<AgentId>();
  const rows: Array<{ id: string; agent: AgentId; project?: string; model?: string; ago?: number; live?: string; attention?: boolean }> = USAGE_SESSIONS.map((session) => {
    const ago = session.ago + tick;
    const agent = working.find((item) => item.id === session.agent);
    if (agent && !claimed.has(agent.id) && ago < 15 * 60) {
      claimed.add(agent.id);
      return { ...session, ago, live: demo.agentStatus(agent), attention: agent.attention };
    }
    return { ...session, ago };
  });
  working.filter((agent) => !claimed.has(agent.id)).forEach((agent) => {
    rows.push({ id: `live:${agent.id}`, agent: agent.id, live: demo.agentStatus(agent), attention: agent.attention });
  });
  const sessions = rows
    .sort((a, b) => (a.live ? 0 : 1) - (b.live ? 0 : 1) || (a.ago ?? Infinity) - (b.ago ?? Infinity))
    .slice(0, 3);

  const peak = Math.max(...summary.trend.map((bar) => bar.claude + bar.codex), 1);
  const dense = summary.trend.length > 12;
  const step = demo.usageRange === 'today' ? 6 : demo.usageRange === 'week' ? 1 : 5;
  const label = (date: Date) => {
    if (demo.usageRange === 'today') {
      const hour = date.getHours();
      return `${hour % 12 === 0 ? 12 : hour % 12}${hour < 12 ? 'a' : 'p'}`;
    }
    if (demo.usageRange === 'week') return 'SMTWTFS'[date.getDay()];
    return String(date.getDate());
  };

  return (
    <div className="ap-stack">
      <div className="ap-dashboard-row">
        {USAGE_PROVIDERS.map((provider) => (
          <div className="ap-card ap-dashboard-card" key={provider.id}>
            <CardHeader title={agentName(provider.id)} mark={provider.id} detail={provider.model}>
              <span className="ap-plan" style={css({ '--tint': agentTint(provider.id) })}>{provider.plan}</span>
            </CardHeader>
            {provider.limits.map((limit) => {
              const remaining = Math.max(limit.resets - tick, 0);
              const pace = Math.min(Math.max(1 - remaining / limit.window, 0), 1);
              const near = limit.used >= 90;
              return (
                <div className="ap-limit" key={limit.label} aria-label={`${limit.label} limit, ${limit.used} percent used, renews in ${countdownString(remaining)}`}>
                  <span className="ap-limit__line">
                    <span className="ap-limit__label">{limit.label}</span>
                    <span className="ap-limit__reset"><Sym name="arrow.clockwise" size={8} />{countdownString(remaining)}</span>
                    <span className="ap-spacer" />
                    <b className={near ? 'is-warning' : undefined}>{limit.used}%</b>
                  </span>
                  <span className="ap-limit__bar">
                    <i style={{ width: `max(${limit.used}%, 5px)`, background: near ? '#fa5959' : agentTint(provider.id) }} />
                    <u style={{ left: `calc(${pace * 100}% - .75px)` }} />
                  </span>
                </div>
              );
            })}
            {provider.observedAgo + tick > 15 * 60 && <small className="ap-footnote ap-tertiary">Updated {agoString(provider.observedAgo + tick)}</small>}
          </div>
        ))}
      </div>

      <div className="ap-dashboard-row">
        <div className="ap-card ap-dashboard-card ap-spending">
          <CardHeader title="Spending" symbol="dollarsign.circle">
            <ChipPicker label="Spending range" options={RANGES.map((item) => ({ id: item.id, title: item.short }))} value={demo.usageRange} onChange={demo.setUsageRange} />
          </CardHeader>
          <span className="ap-spend"><b>{usdString(total.cost)}</b><small>API value</small></span>
          <span className="ap-share" aria-hidden="true">
            {PROVIDERS.map((id) => <i key={id} style={{ flexGrow: summary[id].cost, background: agentTint(id) }} />)}
          </span>
          <span className="ap-legend">
            {PROVIDERS.map((id) => (
              <span key={id}><i style={{ background: agentTint(id) }} />{agentName(id)}<b>{usdString(summary[id].cost)}</b></span>
            ))}
          </span>
          <small className="ap-footnote ap-tertiary">{tokenString(total.tokens)} tokens · 97% from cache</small>
        </div>

        <div className="ap-card ap-dashboard-card ap-sessions">
          <CardHeader title="Sessions" symbol="waveform.path.ecg" />
          {sessions.map((row) => (
            <div className="ap-session" key={row.id}>
              <span className="ap-session__mark">
                {row.live ? <AgentOrb id={row.agent} size={20} attention={row.attention} /> : <PixelMark id={row.agent} width={13} />}
              </span>
              <span className="ap-text">
                <b>{row.project ?? agentName(row.agent)}</b>
                {row.live
                  ? <small style={{ color: row.attention ? 'var(--ap-attention)' : agentTint(row.agent), fontWeight: 500 }}>{row.live}</small>
                  : row.model && <small className="ap-tertiary">{row.model}</small>}
              </span>
              <time className={row.attention ? 'is-attention' : undefined}>
                {row.attention ? 'Needs you' : row.live ? (row.model ?? 'Working') : row.ago !== undefined ? agoString(row.ago) : '—'}
              </time>
            </div>
          ))}
        </div>
      </div>

      <div className="ap-card ap-breakdown">
        <div className="ap-card-header">
          <span className="ap-card-header__icon"><Sym name={BREAKDOWNS.find((item) => item.id === breakdown)!.symbol} size={11} /></span>
          <ChipPicker label="Breakdown" options={BREAKDOWNS} value={breakdown} onChange={setBreakdown} size={10.5} />
          <span className="ap-spacer" />
          <small className="ap-footnote ap-tertiary ap-digits">{range.title} · {tokenString(total.tokens)} tokens</small>
        </div>
        <div className="ap-breakdown__body">
          {breakdown === 'trend' ? (
            <div className={`ap-trend${dense ? ' is-dense' : ''}`} aria-label={`Usage trend, ${range.title}`}>
              <div className="ap-trend__bars">
                {summary.trend.map((bar, index) => (
                  <span key={index}>
                    {bar.claude + bar.codex === 0 ? <i className="is-empty" /> : (
                      <>
                        {bar.codex > 0 && <i style={{ height: `max(2px, ${(bar.codex / peak) * 44}px)`, background: agentTint('codex') }} />}
                        {bar.claude > 0 && <i style={{ height: `max(2px, ${(bar.claude / peak) * 44}px)`, background: agentTint('claude') }} />}
                      </>
                    )}
                  </span>
                ))}
              </div>
              <div className="ap-trend__labels">
                {summary.trend.map((bar, index) => <small key={index}>{index % step === 0 ? label(bar.start) : ''}</small>)}
              </div>
            </div>
          ) : (
            <div className="ap-breakdown__list">
              {USAGE_BREAKDOWNS[breakdown].slice(0, 3).map((row) => (
                <div className="ap-breakdown__row" key={row.name}>
                  <i style={{ background: agentTint(row.agent) }} />
                  <b>{row.name}</b>
                  <span className="ap-spacer" />
                  <span className="ap-breakdown__bar"><i style={{ width: `${(row.cost / USAGE_BREAKDOWNS[breakdown][0].cost) * 100}%`, background: agentTint(row.agent) }} /></span>
                  <small>{tokenString(row.tokens * scale)}</small>
                  <strong>{usdString(row.cost * scale)}</strong>
                </div>
              ))}
              {USAGE_BREAKDOWNS[breakdown].length > 3 && (() => {
                const rest = USAGE_BREAKDOWNS[breakdown].slice(3);
                const tokens = rest.reduce((sum, row) => sum + row.tokens, 0) * scale;
                const cost = rest.reduce((sum, row) => sum + row.cost, 0) * scale;
                return <small className="ap-caption ap-tertiary">+{rest.length} more · {tokenString(tokens)} tokens · {usdString(cost)}</small>;
              })()}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/* ── Capture · QuickCaptureWidget ────────────────────────── */

function CaptureWidget({ demo }: { demo: Demo }) {
  const [searching, setSearching] = useState(false);
  const [query, setQuery] = useState('');
  const field = useRef<HTMLInputElement>(null);
  const accent = demo.accentHex;
  const canSave = demo.draft.trim().length > 0;
  const items = demo.captures.filter((item) => !query.trim() || item.text.toLowerCase().includes(query.trim().toLowerCase()));

  useEffect(() => {
    if (searching) field.current?.focus();
  }, [searching]);

  return (
    <div className="ap-list-widget">
      <div className="ap-input-row">
        <label className="ap-field">
          <Sym name={searching ? 'magnifyingglass' : 'square.and.pencil'} size={9} className={searching ? 'ap-tertiary' : 'ap-accent'} />
          {searching ? (
            <input ref={field} value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search captures" aria-label="Search Quick Captures" onClick={(event) => event.stopPropagation()} />
          ) : (
            <input
              value={demo.draft}
              onChange={(event) => demo.setDraft(event.target.value)}
              onKeyDown={(event) => { if (event.key === 'Enter') demo.saveDraft(); }}
              placeholder="Capture a note or link…"
              aria-label="Quick Capture text"
              onClick={(event) => event.stopPropagation()}
            />
          )}
        </label>
        {searching ? (
          <NotchButton symbol="xmark" size={9} label="Close capture search" tint={SECONDARY} onClick={() => { setSearching(false); setQuery(''); }} />
        ) : (
          <>
            <NotchButton symbol="sparkles" size={9} label="Enhance with Apple Intelligence" tint={canSave ? accent : 'var(--ap-tertiary)'} disabled={!canSave} />
            <NotchButton symbol="doc.on.clipboard" size={9} label="Paste clipboard" tint={SECONDARY} onClick={demo.pasteIntoDraft} />
            <NotchButton symbol="arrow.up" size={9} label="Save capture" tint={canSave ? accent : 'var(--ap-tertiary)'} disabled={!canSave} onClick={demo.saveDraft} />
          </>
        )}
      </div>

      {demo.captures.length === 0 ? (
        <EmptyState symbol="square.and.pencil" title="Capture something" subtitle="Type a note or paste selected text, then press Return." />
      ) : items.length === 0 ? (
        <EmptyState symbol="magnifyingglass" title="No matches" subtitle="Try a different search." />
      ) : (
        <>
          <ListHeader title={`${items.length} capture${items.length === 1 ? '' : 's'}`}>
            {!searching && <TextButton onClick={() => setSearching(true)}>Search</TextButton>}
            <TextButton onClick={() => demo.setCaptures([])}>Clear</TextButton>
          </ListHeader>
          <div className="ap-scroll">
            {items.map((item) => (
              <div className="ap-row ap-item" key={item.id}>
                <span className="ap-item__main">
                  <span className="ap-thumb"><Sym name={isLink(item.text) ? 'link' : 'note.text'} size={10.5} /></span>
                  <span className="ap-text">
                    <b>{item.text}</b>
                    <small>{captureDetail(item, demo.loadedAt) || ' '}</small>
                  </span>
                </span>
                <NotchButton
                  symbol={item.pinned ? 'pin.fill' : 'pin'}
                  size={8.5}
                  label={item.pinned ? 'Unpin capture' : 'Pin capture'}
                  tint={item.pinned ? accent : 'var(--ap-tertiary)'}
                  onClick={() => demo.setCaptures((current) => current.map((capture) => (capture.id === item.id ? { ...capture, pinned: !capture.pinned } : capture)))}
                />
                <NotchButton symbol="xmark" size={8} label="Remove capture" tint="var(--ap-tertiary)" onClick={() => demo.setCaptures((current) => current.filter((capture) => capture.id !== item.id))} />
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

/* ── Shortcuts · CustomShortcutsWidget ───────────────────── */

function ShortcutsWidget({ demo }: { demo: Demo }) {
  return (
    <div className="ap-shortcuts">
      <div className="ap-shortcut-grid">
        {CUSTOM_ACTIONS.map((action) => (
          <button
            key={action.id}
            type="button"
            className="ap-shortcut"
            title={`${action.title} · ${actionSubtitle(action)}`}
            onClick={(event) => {
              event.stopPropagation();
              demo.perform(action);
            }}
          >
            {action.kind === 'app' ? (
              <Image className="ap-shortcut__app" src={action.icon} alt="" width={52} height={52} />
            ) : (
              <span className="ap-shortcut__icon"><Sym name={actionSymbol(action)} size={12} /></span>
            )}
            <span className="ap-text">
              <b>{action.title}</b>
              <small>{actionSubtitle(action)}</small>
            </span>
          </button>
        ))}
      </div>
      {demo.feedback && (
        <span className={`ap-feedback${demo.feedback.error ? ' is-error' : ''}`} role="status">
          <Sym name={demo.feedback.error ? 'exclamationmark.triangle.fill' : 'checkmark.circle.fill'} size={9.5} />
          {demo.feedback.message}
        </span>
      )}
    </div>
  );
}

/* ── Music · MusicWidget ─────────────────────────────────── */

function MusicWidget({ demo }: { demo: Demo }) {
  const accent = demo.accentHex;
  const { track, music } = demo;
  return (
    <div className="ap-card ap-player">
      <div className="ap-player__head">
        <Artwork src={track.artwork} width={56} height={56} radius={9} />
        <span className="ap-text">
          <b>{track.title}</b>
          <span className="ap-player__subtitle"><small>{track.artist} — {track.album}</small><em>Spotify</em></span>
        </span>
      </div>
      <div className="ap-player__progress">
        <Meter value={music.position / track.duration} tint={accent} height={3} />
        <span><small>{clockString(music.position)}</small><small>{clockString(track.duration)}</small></span>
      </div>
      <div className="ap-player__controls">
        <NotchButton symbol="backward.fill" size={11} label="Previous" onClick={demo.previousTrack} />
        <NotchButton symbol={music.playing ? 'pause.fill' : 'play.fill'} size={12} prominent tint={accent} label={music.playing ? 'Pause' : 'Play'} onClick={demo.playPause} />
        <NotchButton symbol="forward.fill" size={11} label="Next" onClick={demo.nextTrack} />
        <span className="ap-spacer" />
        <AudioBars playing={music.playing} tint={accent} />
      </div>
    </div>
  );
}

/* ── System · SystemWidget ───────────────────────────────── */

const LOAD = [0.3, 0.27, 0.34, 0.41, 0.29];
const MEMORY = [0.78, 0.79, 0.77, 0.8, 0.78];
const NETWORK = [[12e3, 191e3], [3.2e6, 118e3], [480e3, 64e3], [5.1e6, 240e3]];

function SystemWidget({ demo }: { demo: Demo }) {
  const accent = demo.accentHex;
  const sample = Math.floor(demo.tick / 2);
  const cpu = LOAD[sample % LOAD.length];
  const memory = MEMORY[sample % MEMORY.length];
  const [down, up] = NETWORK[sample % NETWORK.length];
  /** Accent until 60%, amber until 85%, then red. */
  const load = (value: number) => (value < 0.6 ? accent : value < 0.85 ? '#fcb840' : '#fa5959');
  /** Green while charging; red under 15%, amber under 30%, else accent. */
  const battery = (level: number, charging: boolean) => (charging ? '#52cc8c' : level < 0.15 ? '#fa5959' : level < 0.3 ? '#fcb840' : accent);
  const rate = (value: number) => `${byteString(value)}/s`;
  const devices = [
    { name: 'This Mac', level: 1, charging: false, symbol: 'laptopcomputer' },
    { name: 'Magic Keyboard', level: 0.82, charging: false, symbol: 'keyboard' },
    { name: 'Magic Mouse', level: 0.17, charging: false, symbol: 'computermouse' },
    { name: 'Headphones', level: 0.63, charging: true, symbol: 'headphones' },
  ];

  return (
    <div className="ap-stack">
      <div className="ap-gauges">
        {[['CPU', cpu], ['Memory', memory]].map(([title, value]) => (
          <div className="ap-card ap-gauge" key={title as string}>
            <span className="ap-gauge__ring">
              <Ring value={value as number} tint={load(value as number)} line={3.5} size={38} />
              <b>{Math.floor((value as number) * 100)}%</b>
            </span>
            <small>{title}</small>
          </div>
        ))}
        <div className="ap-card ap-gauge">
          <span className="ap-gauge__ring" style={{ color: battery(1, false) }}>
            <Ring value={1} tint={battery(1, false)} line={3.5} size={38} />
            <Sym name="battery.100percent" size={11} />
          </span>
          <small>100%</small>
        </div>
        <div className="ap-card ap-network">
          <span><Sym name="arrow.down" size={8} className="ap-accent" />{rate(down)}</span>
          <span><Sym name="arrow.up" size={8} className="ap-secondary" />{rate(up)}</span>
          <small>Network</small>
        </div>
      </div>

      <div className="ap-card ap-devices">
        <div className="ap-devices__head">
          <Sym name="battery.100percent" size={9} className="ap-accent" />
          <b>Device batteries</b>
          <span className="ap-spacer" />
          <small>{devices.length} devices</small>
        </div>
        <div className="ap-devices__cells">
          {devices.map((device) => {
            const tint = battery(device.level, device.charging);
            return (
              <span className="ap-device" key={device.name} title={`${device.name}: ${Math.round(device.level * 100)}%${device.charging ? ' · Charging' : ''}`}>
                <i style={css({ '--tint': tint })}><Sym name={device.charging ? 'bolt.fill' : device.symbol} size={9} /></i>
                <span className="ap-text">
                  <b>{device.name}</b>
                  <small style={{ color: tint }}>{Math.round(device.level * 100)}%</small>
                </span>
              </span>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/* ── Live · LiveActivityWidget ───────────────────────────── */

function LiveWidget({ demo }: { demo: Demo }) {
  if (!demo.build) {
    return <EmptyState symbol="waveform.path.ecg" title="No live activities" subtitle="Start one from a script, Shortcut, or terminal." />;
  }
  return (
    <div className="ap-scroll">
      <div className="ap-row">
        <LiveRow title="Building release" subtitle="Running tests" progress={demo.build.progress} accent={demo.accentHex} />
      </div>
    </div>
  );
}

/* ── Files · FileActivityWidget ──────────────────────────── */

function FilesWidget({ demo }: { demo: Demo }) {
  if (demo.files.length === 0) {
    return <EmptyState symbol="arrow.down.circle" title="No recent transfers" subtitle="Downloads appear here as they arrive." />;
  }
  const finished = demo.files.some((file) => file.complete);
  return (
    <div className="ap-list-widget">
      <ListHeader title={`${demo.files.length} transfer${demo.files.length === 1 ? '' : 's'}`}>
        {finished && <TextButton onClick={() => demo.setFiles((current) => current.filter((file) => !file.complete))}>Clear finished</TextButton>}
      </ListHeader>
      <div className="ap-scroll">
        {demo.files.map((file) => (
          <div className="ap-row ap-file" key={file.id}>
            <Image src={`/file-icons/${file.icon}.png`} alt="" width={48} height={48} />
            <span className="ap-text">
              <b>{file.name}</b>
              {file.complete
                ? <small className="ap-tertiary">{byteString(file.bytes)}</small>
                : <small className="ap-secondary ap-digits">{byteString(file.bytes)}{file.rate > 1024 ? ` · ${byteString(file.rate)}/s` : ''}</small>}
            </span>
            {file.complete
              ? <NotchButton symbol="magnifyingglass" size={10} label={`Reveal ${file.name} in Finder`} tint={SECONDARY} />
              : <span className="ap-spinner" aria-label="Downloading" />}
          </div>
        ))}
      </div>
    </div>
  );
}

/* ── Activity · ActivityWidget ───────────────────────────── */

function eventTime(event: NotchEvent, loadedAt: Date | null) {
  if (!loadedAt) return '';
  const at = 'ago' in event.at ? loadedAt.getTime() - event.at.ago * 1000 : loadedAt.getTime() + event.at.tick * 1000;
  return timeOfDay(new Date(at));
}

/** EventIcon: the agent's own mark for agent events, else the kind's symbol. */
export function EventIcon({ event, size }: { event: NotchEvent; size: number }) {
  if (event.agent) return <PixelMark id={event.agent} width={size * (event.agent === 'claude' ? 1.6 : 1)} />;
  const kind = EVENT_KINDS[event.kind];
  return <span style={{ color: kind.tint, display: 'inline-flex' }}><Sym name={kind.symbol} size={size} /></span>;
}

function ActivityWidget({ demo }: { demo: Demo }) {
  if (demo.events.length === 0) {
    return <EmptyState symbol="bell.slash" title="Nothing yet" subtitle="Track changes, downloads and power events land here." />;
  }
  return (
    <div className="ap-list-widget">
      <ListHeader title="Recent">
        <TextButton onClick={() => demo.setEvents([])}>Clear</TextButton>
      </ListHeader>
      <div className="ap-scroll">
        {demo.events.map((event) => (
          <div className="ap-row ap-event" key={event.id}>
            <span className="ap-event__icon"><EventIcon event={event} size={11} /></span>
            <span className="ap-text">
              <b>{event.title}</b>
              {event.subtitle && <small className="ap-tertiary">{event.subtitle}</small>}
            </span>
            <time>{eventTime(event, demo.loadedAt)}</time>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ── Clipboard · ClipboardWidget ─────────────────────────── */

function ClipboardWidget({ demo }: { demo: Demo }) {
  const [query, setQuery] = useState('');
  const accent = demo.accentHex;
  const items = demo.clipboard.filter((item) => !query.trim() || item.text.toLowerCase().includes(query.trim().toLowerCase()));
  return (
    <div className="ap-list-widget ap-list-widget--loose">
      <div className="ap-input-row">
        <label className="ap-field ap-field--short">
          <Sym name="magnifyingglass" size={9} className="ap-tertiary" />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search clipboard" aria-label="Search clipboard history" onClick={(event) => event.stopPropagation()} />
        </label>
        <NotchButton
          symbol={demo.clipboardPaused ? 'play.fill' : 'pause.fill'}
          size={9}
          label={demo.clipboardPaused ? 'Resume capture' : 'Pause capture'}
          tint={demo.clipboardPaused ? accent : SECONDARY}
          onClick={() => demo.setClipboardPaused(!demo.clipboardPaused)}
        />
        <NotchButton symbol="trash" size={9} label="Clear history" tint={SECONDARY} disabled={demo.clipboard.length === 0} onClick={() => demo.setClipboard([])} />
      </div>
      {demo.clipboard.length === 0 ? (
        <EmptyState
          symbol={demo.clipboardPaused ? 'pause.fill' : 'doc.on.clipboard'}
          title={demo.clipboardPaused ? 'Capture paused' : 'Clipboard is empty'}
          subtitle={demo.clipboardPaused ? 'Resume when you want to capture again.' : 'Copy text, links or images to keep them here.'}
        />
      ) : items.length === 0 ? (
        <EmptyState symbol="magnifyingglass" title="No matches" subtitle="Try a different search." />
      ) : (
        <div className="ap-scroll">
          {items.map((item) => (
            <div className="ap-row ap-item" key={item.id}>
              <span className="ap-item__main">
                {item.kind === 'image'
                  ? <span className="ap-thumb ap-thumb--image"><Image src="/og.jpg" alt="" width={50} height={50} /></span>
                  : <span className="ap-thumb"><Sym name={clipboardSymbol(item.kind)} size={11} /></span>}
                <span className="ap-text">
                  <b>{item.kind === 'image' ? 'Image' : item.text}</b>
                  <small>{clipboardDetail(item)}</small>
                </span>
              </span>
              <NotchButton
                symbol={item.pinned ? 'pin.fill' : 'pin'}
                size={8.5}
                label={item.pinned ? 'Unpin item' : 'Pin item'}
                tint={item.pinned ? accent : 'var(--ap-tertiary)'}
                onClick={() => demo.setClipboard((current) => current.map((entry) => (entry.id === item.id ? { ...entry, pinned: !entry.pinned } : entry)))}
              />
              <NotchButton symbol="xmark" size={8} label="Remove item" tint="var(--ap-tertiary)" onClick={() => demo.setClipboard((current) => current.filter((entry) => entry.id !== item.id))} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/* ── Shelf · ShelfWidget ─────────────────────────────────── */

function ShelfWidget({ demo }: { demo: Demo }) {
  if (demo.shelf.length === 0) {
    return <EmptyState symbol="tray" title="Shelf is empty" subtitle="Drag files onto the notch to park them here." />;
  }
  return (
    <div className="ap-list-widget ap-list-widget--loose">
      <ListHeader title={`${demo.shelf.length} item${demo.shelf.length === 1 ? '' : 's'}`}>
        <TextButton onClick={() => demo.setShelf([])}>Clear</TextButton>
      </ListHeader>
      <div className="ap-shelf">
        {demo.shelf.map((item) => (
          <div className="ap-shelf__tile" key={item.id} title={item.name}>
            <Image src={`/file-icons/${item.icon}.png`} alt="" width={68} height={68} />
            <small>{item.name}</small>
            <NotchButton symbol="xmark.circle.fill" size={9} label={`Remove ${item.name} from shelf`} tint="var(--ap-tertiary)" className="ap-shelf__remove" onClick={() => demo.setShelf((current) => current.filter((entry) => entry.id !== item.id))} />
          </div>
        ))}
      </div>
    </div>
  );
}

/* ── Command palette · CommandPaletteView ────────────────── */

function Palette({ demo }: { demo: Demo }) {
  const input = useRef<HTMLInputElement>(null);
  const [focused, setFocused] = useState(false);
  useEffect(() => {
    input.current?.focus({ preventScroll: true });
  }, []);

  return (
    <div className="ap-palette" role="dialog" aria-label="Command Palette">
      <div className={`ap-palette__field${focused ? ' is-focused' : ''}`}>
        <Sym name="magnifyingglass" size={13} className="ap-accent" />
        <input
          ref={input}
          value={demo.query}
          onChange={(event) => demo.setQuery(event.target.value)}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          onClick={(event) => event.stopPropagation()}
          onKeyDown={(event) => {
            if (event.key === 'ArrowDown') { event.preventDefault(); demo.moveSelection(1); }
            else if (event.key === 'ArrowUp') { event.preventDefault(); demo.moveSelection(-1); }
            else if (event.key === 'Enter') { const command = demo.results[demo.selected]; if (command) demo.runCommand(command); }
            else if (event.key === 'Escape') { event.stopPropagation(); demo.closePalette(); }
          }}
          placeholder="Search commands, captures, files…"
          aria-label="Search commands, captures, files"
        />
        {demo.query ? (
          <button type="button" className="ap-palette__clear" aria-label="Clear search" onClick={(event) => { event.stopPropagation(); demo.setQuery(''); input.current?.focus(); }}>
            <Sym name="xmark.circle.fill" size={11} />
          </button>
        ) : (
          <kbd>{PALETTE_SHORTCUT}</kbd>
        )}
      </div>

      {demo.results.length === 0 ? (
        <div className="ap-palette__empty">
          <Sym name="sparkle.magnifyingglass" size={17} />
          <b>No matching command</b>
          <small>Try an app, widget, capture, or settings page</small>
        </div>
      ) : (
        <div className="ap-palette__results" role="listbox" aria-label="Commands">
          {demo.results.map((command, index) => (
            <button
              key={command.id}
              type="button"
              role="option"
              aria-selected={index === demo.selected}
              className={`ap-command${index === demo.selected ? ' is-selected' : ''}`}
              onMouseEnter={() => demo.setSelected(index)}
              onClick={(event) => { event.stopPropagation(); demo.runCommand(command); }}
            >
              <span className="ap-command__icon"><Sym name={command.symbol} size={11} /></span>
              <span className="ap-text">
                <b>{command.title}</b>
                <small>{command.subtitle}</small>
              </span>
              <em>{command.category}</em>
              {index === demo.selected && <Sym name="return" size={8} className="ap-tertiary" />}
            </button>
          ))}
        </div>
      )}

      <div className="ap-palette__footer">
        <span><Sym name="arrow.up.arrow.down" size={9.5} />Navigate</span>
        <span><Sym name="return" size={9.5} />Run</span>
        <span className="ap-spacer" />
        <button type="button" onClick={(event) => { event.stopPropagation(); demo.closePalette(); }}>Close</button>
      </div>
    </div>
  );
}
