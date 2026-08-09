import { features } from '@/content/site';

export default function Features() {
  return (
    <section id="features" className="section">
      <div className="wrap">
        <div className="slab">
          <header className="slab__head">
            <p className="label">The complete toolkit</p>
            <h2 className="title">Everything your notch can do. One calmer desktop.</h2>
            <p className="lede">
              Every part of Bondex answers a question you&apos;d otherwise open an
              app to answer. Keep the widgets you need, reorder them, and switch
              the rest off completely.
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
