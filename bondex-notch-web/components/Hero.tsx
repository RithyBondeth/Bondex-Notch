import NotchDemo from './NotchDemo';
import { GITHUB_REPO_URL } from '@/lib/public-config';

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
          Capture thoughts, run focus sessions, join meetings, control music and
          follow agents, downloads and system health — all where your eyes already
          pass. Bondex appears when it matters and melts back when it doesn&apos;t.
        </p>

        <div className="actions">
          <a className="btn" href="/download/">
            Download for Mac
          </a>
          <a className="btn btn--ghost" href={GITHUB_REPO_URL}>
            View source on GitHub
          </a>
        </div>

        <p className="meta">
          macOS 14+ · Free and open source · No account required · Everything stays on your Mac
        </p>

        <div className="hero__signals" aria-label="Highlights">
          <span><i className="pulse-dot" /> Agent activity</span>
          <span>✎ Quick Capture</span>
          <span>◷ Focus &amp; meetings</span>
          <span>⌕ Command palette</span>
        </div>

        <NotchDemo />
      </div>
    </section>
  );
}
