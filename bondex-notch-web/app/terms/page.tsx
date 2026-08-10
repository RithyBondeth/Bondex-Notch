import type { Metadata } from 'next';
import Link from 'next/link';
import LegalPage from '@/components/LegalPage';
import { SUPPORT_EMAIL, supportMailto } from '@/lib/public-config';

export const metadata: Metadata = {
  title: 'Terms of Use — Bondex Notch',
  description: 'Terms for the Bondex Notch website, trial, software, and licence.',
  alternates: { canonical: '/terms/' },
};

export default function TermsPage() {
  return (
    <LegalPage
      currentPath="/terms/"
      eyebrow="Clear terms, no feature tiers"
      title="Terms of Use"
      intro="These terms govern your use of the Bondex Notch website, 24-hour trial, software, and any licence you later purchase."
    >
      <section>
        <h2>1. Agreement and operator</h2>
        <p>
          By downloading, installing, or using Bondex Notch, you agree to these
          terms. Bondex Notch is independently developed and operated by Rithy
          Bondeth in Cambodia. If you do not agree, do not use the software.
          Questions can be sent to{' '}
          <a href={supportMailto('Bondex Notch terms')}>
            {SUPPORT_EMAIL}
          </a>
          .
        </p>
      </section>

      <section className="legal-callout">
        <h2>2. Purchases and payment</h2>
        <p>
          When paid checkout is available, payments are processed on Stripe&apos;s
          hosted checkout. A purchase agreement is formed only when Stripe
          accepts payment and provides an order confirmation. The final price,
          taxes, licence scope, and payment method are shown before purchase. If
          the checkout button says setup is still in progress, paid sales are not
          yet open.
        </p>
      </section>

      <section>
        <h2>3. The 24-hour trial</h2>
        <p>
          The trial begins on first launch and provides the complete app for 24
          hours. After it expires, app functionality is locked until a valid
          licence is activated. You may not manipulate the clock, stored trial
          state, app files, or other technical measures to extend or restart the
          trial. Reinstalling the app does not grant a contractual right to a new
          trial.
        </p>
      </section>

      <section>
        <h2>4. Software licence</h2>
        <p>
          After a valid purchase, Bondex grants you a limited, personal,
          non-exclusive, non-transferable licence to use the purchased version on
          Macs you own or control, unless the purchase confirmation states a
          different device scope. The licence is a right to use the software, not
          a sale of its source code, branding, or intellectual property.
        </p>
        <p>
          A lifetime licence means you may keep using the version you purchased
          for as long as it remains compatible with your hardware and macOS. It
          does not promise perpetual compatibility, every future major version,
          or an unlimited period of updates or support unless expressly stated at
          purchase.
        </p>
      </section>

      <section>
        <h2>5. Acceptable use</h2>
        <p>You may not:</p>
        <ul>
          <li>share, resell, publish, or generate licence keys without permission;</li>
          <li>circumvent trial, licence, security, or access controls;</li>
          <li>use the software to violate law or another person&apos;s rights;</li>
          <li>redistribute or commercially host the software as your own product; or</li>
          <li>reverse engineer the software except where applicable law expressly permits it.</li>
        </ul>
      </section>

      <section>
        <h2>6. Updates and third-party services</h2>
        <p>
          We may add, change, or discontinue features and integrations. Bondex
          works with macOS and third-party apps such as media players, browsers,
          calendars, coding agents, and communication tools. Their availability,
          interfaces, and terms are outside our control. You are responsible for
          using those services lawfully and maintaining compatible software.
        </p>
      </section>

      <section>
        <h2>7. Warranty and liability</h2>
        <p>
          To the extent permitted by law, Bondex is provided “as is” and “as
          available,” without warranties that it will always be uninterrupted,
          error-free, or compatible with every Mac, display, app, or future macOS
          version. Nothing in these terms excludes warranties or remedies that
          cannot legally be excluded.
        </p>
        <p>
          To the extent permitted by law, Bondex and its operator are not liable
          for indirect, incidental, special, or consequential loss, loss of data,
          or loss caused by third-party services. Any aggregate liability arising
          from a paid licence is limited to the amount you paid for that licence,
          except where applicable law does not allow that limit.
        </p>
      </section>

      <section>
        <h2>8. Suspension, termination, and refunds</h2>
        <p>
          We may suspend or revoke a licence obtained fraudulently, shared in
          violation of these terms, or used to abuse the service. You may stop
          using Bondex at any time. Eligible purchase refunds are governed by the{' '}
          <Link href="/refunds/">Refund Policy</Link>. Sections intended to survive
          termination—including ownership, disclaimers, liability limits, and
          dispute terms—continue to apply.
        </p>
      </section>

      <section>
        <h2>9. Governing law and changes</h2>
        <p>
          These terms are governed by the laws of Cambodia, without removing any
          mandatory consumer protection that applies where you live. Before
          starting formal proceedings, please contact us so we can try to resolve
          the issue in good faith. Disputes that cannot be resolved are subject
          to the competent courts of Cambodia, unless applicable law gives you a
          different mandatory forum.
        </p>
        <p>
          We may update these terms for legal, security, payment, or product
          changes. Material changes apply prospectively and will be identified by
          a new effective date.
        </p>
      </section>
    </LegalPage>
  );
}
