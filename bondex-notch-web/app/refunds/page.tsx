import type { Metadata } from 'next';
import LegalPage from '@/components/LegalPage';

export const metadata: Metadata = {
  title: 'Refund Policy — Bondex Notch',
  description: 'When and how to request a refund for a Bondex Notch licence.',
  alternates: { canonical: '/refunds/' },
};

export default function RefundsPage() {
  return (
    <LegalPage
      currentPath="/refunds/"
      eyebrow="A fair purchase policy"
      title="Refund Policy"
      intro="The complete app is available during a free 24-hour trial so you can check compatibility before buying. When paid sales open, the policy below will apply."
    >
      <section className="legal-callout">
        <h2>Sales are not open yet</h2>
        <p>
          The current checkout is a preview. It does not charge cards or issue
          production licences, so there are currently no website purchases to
          refund. This page states the policy that will apply when payment
          processing is enabled.
        </p>
      </section>

      <section>
        <h2>1. Fourteen-day voluntary refund window</h2>
        <p>
          You may request a refund within 14 calendar days after the original
          purchase date. Email{' '}
          <a href="mailto:rithybondeth999@gmail.com?subject=Bondex%20Notch%20refund%20request">
            rithybondeth999@gmail.com
          </a>{' '}
          from the address used for purchase and include your order number. You
          do not need to publish your licence key or card details.
        </p>
      </section>

      <section>
        <h2>2. What happens after approval</h2>
        <p>
          An approved refund is returned to the original payment method. Your
          paid licence may be deactivated, after which the app returns to its
          normal expired-trial state. Processing time depends on the payment
          provider and your bank. Original exchange-rate differences, bank fees,
          or similar third-party charges may not be recoverable by Bondex.
        </p>
      </section>

      <section>
        <h2>3. Requests after 14 days</h2>
        <p>
          After the voluntary window, refunds are generally not offered merely
          because you changed your mind or stopped using a functioning licence.
          Please contact support if a reproducible technical defect prevents the
          app from working on a supported Mac and we cannot provide a reasonable
          fix or workaround. We will review those cases fairly.
        </p>
      </section>

      <section>
        <h2>4. Abuse and duplicate purchases</h2>
        <p>
          We may refuse voluntary refunds involving fraud, repeated policy abuse,
          chargeback manipulation, unauthorised key sharing, or circumvention of
          trial and licence controls. Accidental duplicate purchases should be
          reported promptly and will be investigated using the order records.
        </p>
      </section>

      <section>
        <h2>5. Your legal rights</h2>
        <p>
          This voluntary policy does not limit refund, repair, replacement, or
          other remedies that cannot be excluded under applicable consumer law.
          If the law where you live provides stronger mandatory rights, those
          rights control.
        </p>
      </section>
    </LegalPage>
  );
}
