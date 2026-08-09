import { plans } from '@/content/site';

export default function Pricing() {
  return (
    <section id="pricing" className="section">
      <div className="wrap">
        <div className="slab">
          <header className="slab__head">
            <p className="label">Pricing</p>
            <h2 className="title">Try everything. Then pay once.</h2>
            <p className="lede">
              Your first 24 hours include the complete app—no locked features.
              Purchase one licence to keep using Bondex Notch afterward.
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
