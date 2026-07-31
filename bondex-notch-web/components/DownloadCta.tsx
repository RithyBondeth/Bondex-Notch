export default function DownloadCta() {
  return (
    <section id="download" className="section section--cta">
      <div className="wrap wrap--narrow">
        <p className="label label--light">Get it</p>
        <h2 className="title title--light title--xl">Put the notch to work</h2>
        <p className="lede lede--light">
          Free tier, no account, no telemetry. Build it from source or grab the
          signed release.
        </p>
        <div className="actions actions--center">
          {/* Both are placeholders until there is a release to point at. */}
          <a className="btn" href="#">
            Download for macOS
          </a>
          <a className="btn btn--ghost" href="#">
            View on GitHub
          </a>
        </div>
        <p className="meta">macOS 14+ · Universal binary · ~4 MB</p>
      </div>
    </section>
  );
}
