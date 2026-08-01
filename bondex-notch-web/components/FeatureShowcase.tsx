const trustItems = [
  ['Music', 'Native playback'],
  ['Spotify', 'Native playback'],
  ['Safari + Chrome', 'Browser audio'],
  ['Codex + Claude', 'Agent activity'],
  ['Shortcuts + scripts', 'Live activities'],
];

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
                <li>Verified hooks for Codex and Claude Code</li>
                <li>Readable status from commands, patches and tools</li>
                <li>Completion events flow into your activity history</li>
              </ul>
            </div>

            <div className="product-shot product-shot--agents" role="img" aria-label="Bondex agent activity and live task mockup">
              <span className="shot-notch" />
              <div className="shot-panel">
                <div className="shot-topline">
                  <span>Home</span>
                  <span className="shot-status"><i /> 2 agents active</span>
                </div>
                <div className="agent-list">
                  <div className="agent-row">
                    <span className="agent-orb agent-orb--codex">✦</span>
                    <span><b>Codex</b><small>Implementing the pricing section</small></span>
                    <time>04:18</time>
                  </div>
                  <div className="agent-row">
                    <span className="agent-orb agent-orb--claude">C</span>
                    <span><b>Claude Code</b><small>Running the test suite</small></span>
                    <time>01:37</time>
                  </div>
                </div>
                <div className="live-task">
                  <div className="live-task__top">
                    <span><i>↗</i><b>Building release</b><small>Running tests</small></span>
                    <strong>72%</strong>
                  </div>
                  <span className="progress"><i style={{ width: '72%' }} /></span>
                </div>
              </div>
              <span className="shot-caption">The quietest project manager on your Mac.</span>
            </div>
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

            <div className="product-shot product-shot--media" role="img" aria-label="Bondex music player and system monitor mockup">
              <span className="shot-notch" />
              <div className="shot-panel shot-panel--wide">
                <div className="music-mock">
                  <span className="album-art"><i>W</i></span>
                  <span className="music-copy"><b>Weightless</b><small>Marconi Union</small><span className="progress"><i style={{ width: '38%' }} /></span></span>
                  <span className="transport"><i>‹‹</i><b>Ⅱ</b><i>››</i></span>
                </div>
                <div className="metric-grid">
                  <div><span className="metric-ring" style={{ '--value': '23%' } as React.CSSProperties}><b>23%</b></span><small>CPU</small></div>
                  <div><span className="metric-ring metric-ring--warm" style={{ '--value': '77%' } as React.CSSProperties}><b>77%</b></span><small>Memory</small></div>
                  <div><span className="metric-ring metric-ring--ok" style={{ '--value': '100%' } as React.CSSProperties}><b>⚡</b></span><small>Battery</small></div>
                  <div className="network-metric"><b><i>↓</i> 3.2 MB/s</b><b><i>↑</i> 118 KB/s</b><small>Network</small></div>
                </div>
              </div>
              <span className="shot-caption">Useful information, without another window.</span>
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

            <div className="product-shot product-shot--files" role="img" aria-label="Bondex download tracker and drop shelf mockup">
              <span className="shot-notch" />
              <div className="shot-panel">
                <div className="download-row">
                  <span className="file-icon">ZIP</span>
                  <span><b>Xcode_26.xip</b><small>4.1 GB · 22.4 MB/s</small><span className="progress"><i style={{ width: '64%' }} /></span></span>
                  <strong>64%</strong>
                </div>
                <div className="shelf-label"><span>Drop shelf</span><small>3 items</small></div>
                <div className="shelf-grid">
                  <div><span className="doc-icon doc-icon--blue">FIG</span><small>Mobile flows.fig</small></div>
                  <div><span className="doc-icon doc-icon--pink">PNG</span><small>Hero artwork.png</small></div>
                  <div><span className="doc-icon doc-icon--gold">PDF</span><small>Launch brief.pdf</small></div>
                  <div className="shelf-drop"><b>＋</b><small>Drop here</small></div>
                </div>
              </div>
              <span className="shot-caption">A tiny shelf that follows your focus.</span>
            </div>
          </article>

          <article className="story story--personalize">
            <div className="story__copy">
              <p className="label">04 · Made for your Mac</p>
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

            <div className="settings-shot" role="img" aria-label="Bondex appearance customization mockup">
              <div className="settings-sidebar">
                <b>Bondex Notch</b>
                <span>General</span><span>Widgets</span><span className="is-selected">Appearance</span><span>Permissions</span>
              </div>
              <div className="settings-main">
                <span className="settings-title">Appearance</span>
                <div className="setting-line"><span>Panel material<small>Accent tinted</small></span><i className="select-mock">Tinted⌄</i></div>
                <div className="setting-block"><span>Accent</span><div className="swatches"><i className="swatch is-active" /><i className="swatch" /><i className="swatch" /><i className="swatch" /></div></div>
                <div className="setting-line"><span>Panel width</span><i className="slider-mock"><b style={{ width: '68%' }} /></i><strong>560</strong></div>
                <div className="setting-line"><span>Corner curve</span><i className="slider-mock"><b style={{ width: '46%' }} /></i><strong>22</strong></div>
                <div className="setting-line"><span>Animation speed</span><i className="slider-mock"><b style={{ width: '78%' }} /></i><strong>Fast</strong></div>
                <div className="setting-preview"><span className="setting-notch" /><small>Live preview</small></div>
              </div>
            </div>
          </article>
        </div>
      </div>
    </section>
  );
}
