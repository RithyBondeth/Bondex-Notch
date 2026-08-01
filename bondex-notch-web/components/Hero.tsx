import NotchDemo from './NotchDemo';

export default function Hero() {
  return (
    <section className="hero">
      <div className="wrap">
        <p className="label label--light">A calmer control center for macOS</p>

        {/* The headline opens with a pure CSS animation, so it needs no JS and
            reduced motion lands it on the end state. */}
        <h1 className="hero__title">
          Your Mac&apos;s notch,
          <br />
          <span className="hero__title-b">finally useful.</span>
        </h1>

        <p className="hero__lede">
          Music, downloads, system health, coding agents and live tasks — all in
          the one place your eyes already pass. Bondex appears when it matters
          and melts back into your Mac when it doesn&apos;t.
        </p>

        <div className="actions">
          <a className="btn" href="#download">
            Download for macOS
          </a>
          <a className="btn btn--ghost" href="#how">
            See how it works
          </a>
        </div>

        <p className="meta">
          macOS 14+ · Free to start · No account · Everything stays on your Mac
        </p>

        <div className="hero__signals" aria-label="Highlights">
          <span><i className="pulse-dot" /> Agent activity</span>
          <span>♫ Music &amp; browser audio</span>
          <span>↓ Live downloads</span>
          <span>⌁ CPU, memory &amp; network</span>
        </div>

        <NotchDemo />
      </div>
    </section>
  );
}
