import NotchDemo from './NotchDemo';

export default function Hero() {
  return (
    <section className="hero">
      <div className="wrap">
        <p className="label label--light">Native macOS · Apple silicon &amp; Intel</p>

        {/* The headline opens on Archivo's width axis. Pure CSS animation, so
            it needs no JS and reduced motion lands it on the end state. */}
        <h1 className="hero__title">
          Your Mac&apos;s notch,
          <br />
          <span className="hero__title-b">finally useful.</span>
        </h1>

        <p className="hero__lede">
          Bondex Notch turns the dead space around your camera into a live view
          of what your Mac is doing — the track that&apos;s playing, the file
          that&apos;s downloading, the battery that&apos;s draining. It appears
          when you need it and disappears when you don&apos;t.
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
          macOS 14+ · Free tier · No account · Nothing leaves your Mac
        </p>

        <NotchDemo />
      </div>
    </section>
  );
}
