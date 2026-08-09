import Image from 'next/image';
import AgentPlayground from './AgentPlayground';

const trustItems = [
  ['Music', 'Native playback'],
  ['Spotify', 'Native playback'],
  ['Safari + Chrome', 'Browser audio'],
  ['Codex + Claude', 'Agent activity'],
  ['Quick Capture', 'Notes + links'],
  ['Shortcuts + scripts', 'Actions + activities'],
];

type AppPreviewProps = {
  src: string;
  alt: string;
  label: string;
  width: number;
  height: number;
  className?: string;
};

function AppPreview({ src, alt, label, width, height, className = '' }: AppPreviewProps) {
  return (
    <figure className={`app-preview ${className}`.trim()}>
      <figcaption><span className="app-preview__live" />{label}</figcaption>
      <Image src={src} alt={alt} width={width} height={height} sizes="(max-width: 900px) 86vw, 540px" />
    </figure>
  );
}

export default function FeatureShowcase() {
  return (
    <section id="showcase" className="section showcase">
      <div className="wrap">
        <header className="head head--center showcase__head">
          <p className="label label--light">See the whole picture</p>
          <h2 className="title title--light title--xl">Your work, alive at a glance.</h2>
          <p className="lede lede--light">
            Bondex is more than a media pill. It is a compact, private status layer
            for everything already happening on your Mac.
          </p>
        </header>

        <div className="trust-strip" aria-label="Works with">
          {trustItems.map(([name, detail]) => (
            <span className="trust-item" key={name}>
              <b>{name}</b>
              <small>{detail}</small>
            </span>
          ))}
        </div>

        <div className="stories">
          <article className="story story--agents">
            <div className="story__copy">
              <p className="label">01 · Agent awareness</p>
              <h3>Let your agents work. You&apos;ll know when they&apos;re done.</h3>
              <p>
                Bondex shows which coding agent is active, the task it is working
                through, and a running clock. Multiple agents appear side by side,
                so parallel work never becomes mystery work.
              </p>
              <ul className="story__points">
                <li>Explore the same ten tabs as the real Mac panel</li>
                <li>Signal agents, run builds and simulate downloads</li>
                <li>Control music, change accents and drop files onto Shelf</li>
              </ul>
            </div>

            <AgentPlayground />
          </article>

          <article className="story story--media">
            <div className="story__copy">
              <p className="label">02 · Media + system</p>
              <h3>Control the soundtrack. Keep an eye on the machine.</h3>
              <p>
                See artwork, track, artist and progress from Music, Spotify and
                supported browser players. The same Home view keeps CPU, memory,
                battery and real network throughput one glance away.
              </p>
              <ul className="story__points">
                <li>Playback controls that never steal keyboard focus</li>
                <li>YouTube, SoundCloud, Twitch and more through browser tabs</li>
                <li>Kernel-sampled metrics with an optional compact summary</li>
              </ul>
            </div>

            <div className="app-preview-board app-preview-board--media">
              <AppPreview
                src="/app-previews/music.png"
                alt="The real Bondex Notch Spotify player with playback controls"
                label="Spotify player · rendered by the Mac app"
                width={1120}
                height={560}
              />
              <AppPreview
                src="/app-previews/system.png"
                alt="The real Bondex Notch system panel with CPU, memory, battery, network and device batteries"
                label="System panel · rendered by the Mac app"
                width={1120}
                height={620}
              />
            </div>
          </article>

          <article className="story story--files">
            <div className="story__copy">
              <p className="label">03 · Files in motion</p>
              <h3>Downloads land. Files wait. Your desktop stays clean.</h3>
              <p>
                Watch transfers arrive in Downloads with live size and speed, then
                reveal them in Finder. Drag working files onto the notch to keep a
                temporary shelf available above every app.
              </p>
              <ul className="story__points">
                <li>Live Downloads folder activity and completion banners</li>
                <li>Drag files in, then drag them back out anywhere</li>
                <li>References only — Bondex never duplicates your files</li>
              </ul>
            </div>

            <div className="app-preview-board app-preview-board--files">
              <AppPreview
                src="/app-previews/files.png"
                alt="The real Bondex Notch Files panel in its empty state"
                label="Files · real empty state"
                width={1120}
                height={560}
              />
              <AppPreview
                src="/app-previews/shelf.png"
                alt="The real Bondex Notch Shelf panel holding a folder"
                label="Shelf · real drag-and-drop state"
                width={1120}
                height={560}
              />
            </div>
          </article>

          <article className="story story--productivity">
            <div className="story__copy">
              <p className="label">04 · Capture + act</p>
              <h3>Catch the thought. Find the clipboard. Move on.</h3>
              <p>
                Quick Capture saves notes and links above the app you are already
                using. Session-only clipboard history, a personal shortcut grid and
                one searchable command palette keep routine actions within reach.
              </p>
              <ul className="story__points">
                <li>Search, pin and copy captures without changing windows</li>
                <li>Clipboard text, links and images stay memory-only</li>
                <li>Open apps, run Apple Shortcuts or jump to any widget</li>
              </ul>
            </div>

            <div className="app-preview-board app-preview-board--workflow">
              <AppPreview
                className="app-preview--primary"
                src="/app-previews/capture.png"
                alt="The real Bondex Notch Quick Capture panel with two saved captures"
                label="Quick Capture · rendered by the Mac app"
                width={1120}
                height={560}
              />
              <div className="app-preview-board__pair">
                <AppPreview
                  src="/app-previews/shortcuts.png"
                  alt="The real Bondex Notch Shortcuts grid"
                  label="Shortcuts"
                  width={1120}
                  height={560}
                />
                <AppPreview
                  src="/app-previews/clipboard.png"
                  alt="The real Bondex Notch Clipboard history panel"
                  label="Clipboard"
                  width={1120}
                  height={560}
                />
              </div>
            </div>
          </article>

          <article className="story story--context">
            <div className="story__copy">
              <p className="label">05 · Context aware</p>
              <h3>The right notch for the moment you are in.</h3>
              <p>
                Smart profiles can react to apps, time, power, displays and meetings.
                Focus, calendar and system signals then surface only the context that
                helps — without reading notifications or recording your camera or mic.
              </p>
              <ul className="story__points">
                <li>Work, Meeting, Media and Gaming presets with automatic rules</li>
                <li>Restart-safe focus timer and one-click meeting links</li>
                <li>Hardware HUD, privacy signals and connected-device batteries</li>
              </ul>
            </div>

            <div className="app-preview-board app-preview-board--context">
              <AppPreview
                src="/app-previews/productivity.png"
                alt="The real Bondex Notch Home panel showing focus, a meeting, coding agents and media"
                label="Productivity Home · real app state"
                width={1120}
                height={820}
              />
              <p className="app-preview-board__note"><span>Focus</span><span>Meeting</span><span>Agents</span><span>Media</span></p>
            </div>
          </article>

          <article className="story story--personalize">
            <div className="story__copy">
              <p className="label">06 · Made for your Mac</p>
              <h3>Shape the notch around the way you work.</h3>
              <p>
                Choose what appears, put tabs in your preferred order, and tune the
                panel until it feels native to your setup. Every change applies live,
                with a synthetic pill for displays that have no hardware notch.
              </p>
              <ul className="story__points">
                <li>Custom accent, material, width, opacity and corner geometry</li>
                <li>Reorder tabs and disable any widget completely</li>
                <li>Adjust hover delay, close delay and animation speed</li>
              </ul>
            </div>

            <div className="app-preview-board app-preview-board--settings">
              <AppPreview
                src="/app-previews/settings-appearance.png"
                alt="The real Bondex Notch Appearance settings window"
                label="Appearance settings · rendered by the Mac app"
                width={1400}
                height={997}
              />
            </div>
          </article>
        </div>
      </div>
    </section>
  );
}
