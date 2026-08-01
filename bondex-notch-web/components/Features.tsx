import { features } from '@/content/site';

export default function Features() {
  return (
    <section id="features" className="section">
      <div className="wrap">
        <div className="slab">
          <header className="slab__head">
            <p className="label">Six widgets</p>
            <h2 className="title">Everything at the top of the screen</h2>
            <p className="lede">
              Each widget answers a question you&apos;d otherwise have to open an
              app to answer. Switch one off and it stops sampling entirely.
            </p>
          </header>

          <div className="grid">
            {features.map(({ icon, title, body, tier }) => (
              <article className="feature" key={icon}>
                <span className="feature__icon" data-icon={icon} aria-hidden="true" />
                <h3>{title}</h3>
                <p>{body}</p>
                {tier && <span className="tag">{tier}</span>}
              </article>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
