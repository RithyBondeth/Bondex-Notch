import { supportMailto } from '@/lib/public-config';

export default function ContactCta() {
  const generalQuestion = supportMailto('Question about Bondex Notch');

  return (
    <section id="contact" className="section section--cta">
      <div className="wrap wrap--narrow">
        <p className="label label--light">Available now</p>
        <h2 className="title title--light title--xl">Want Bondex on your Mac?</h2>
        <p className="lede lede--light">
          Download Bondex Notch and use the complete app free for 14 days. For
          licensing, product questions, or feedback, the message goes directly
          to the team building it.
        </p>
        <div className="actions actions--center">
          <a className="btn" href="/download/">
            Download for Mac
          </a>
          <a className="btn btn--ghost" href={generalQuestion}>
            Contact us
          </a>
        </div>
        <p className="meta">Direct reply · 14-day full trial · No account required</p>
      </div>
    </section>
  );
}
