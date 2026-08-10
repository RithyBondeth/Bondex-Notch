import { supportMailto } from '@/lib/public-config';

export default function ContactCta() {
  const earlyAccess = supportMailto('Bondex Notch early access');
  const generalQuestion = supportMailto('Question about Bondex Notch');

  return (
    <section id="contact" className="section section--cta">
      <div className="wrap wrap--narrow">
        <p className="label label--light">Private release</p>
        <h2 className="title title--light title--xl">Want Bondex on your Mac?</h2>
        <p className="lede lede--light">
          Bondex Notch is privately developed. Get in touch for early access,
          licensing, product questions, or feedback—the message goes directly
          to the team building it.
        </p>
        <div className="actions actions--center">
          <a className="btn" href={earlyAccess}>
            Request early access
          </a>
          <a className="btn btn--ghost" href={generalQuestion}>
            Contact us
          </a>
        </div>
        <p className="meta">Direct reply · No public source repository · No account required</p>
      </div>
    </section>
  );
}
