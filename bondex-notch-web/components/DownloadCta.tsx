export default function DownloadCta() {
  const repositoryUrl = 'https://github.com/RithyBondeth/Bondex-Notch';

  return (
    <section id="download" className="section section--cta">
      <div className="wrap wrap--narrow">
        <p className="label label--light">Get it</p>
        <h2 className="title title--light title--xl">Put the notch to work</h2>
        <p className="lede lede--light">
          Free tier, no account, no telemetry. Build the current version from
          source while the first signed release is being prepared.
        </p>
        <div className="actions actions--center">
          <a className="btn" href={`${repositoryUrl}#quick-start`}>
            Build from source
          </a>
          <a className="btn btn--ghost" href={repositoryUrl}>
            View on GitHub
          </a>
        </div>
        <p className="meta">macOS 14+ · Universal binary · ~4 MB</p>
      </div>
    </section>
  );
}
