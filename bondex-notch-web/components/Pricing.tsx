import { plans } from '@/content/site';
import { GITHUB_REPO_URL } from '@/lib/public-config';

export default function Pricing() {
  return (
    <section id="pricing" className="section">
      <div className="wrap">
        <div className="slab">
          <header className="slab__head">
            <p className="label">Open source</p>
            <h2 className="title">Free and open source.</h2>
            <p className="lede">
              Every feature, free for everyone under the MIT License. Read the
              code, build it yourself, or download the ready-made app.
            </p>
          </header>

          <div className="plans">
            {plans.map((plan) => (
              <article
                className={`plan${plan.featured ? ' plan--featured' : ''}`}
                key={plan.name}
              >
                {plan.badge && <span className="plan__badge">{plan.badge}</span>}
                <h3 className="plan__name">{plan.name}</h3>
                <p className="plan__price">
                  <span>{plan.price}</span>
                  {plan.cadence && <small>{plan.cadence}</small>}
                </p>
                <p className="plan__note">{plan.note}</p>
                <ul className="plan__list">
                  {plan.items.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
                {plan.cta && (
                  <a
                    className={`btn btn--block${
                      plan.cta.style === 'ghost' ? ' btn--ghost' : ''
                    }`}
                    href={plan.cta.href}
                  >
                    {plan.cta.label}
                  </a>
                )}
                <div style={{ marginTop: '10px' }}>
                  <a
                    className="btn btn--block btn--ghost"
                    href={GITHUB_REPO_URL}
                    style={{ fontSize: '13px', padding: '10px 16px' }}
                  >
                    View source on GitHub
                  </a>
                </div>
                {plan.unavailable && (
                  <span className="plan__soon">{plan.unavailable}</span>
                )}
              </article>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
