import type { Metadata } from 'next';
import Link from 'next/link';
import BrandMark from '@/components/BrandMark';
import CopyLicenseKey from '@/components/CopyLicenseKey';
import { supportMailto } from '@/lib/public-config';
import { generateLicenseKey } from '@/lib/license';
import {
  getStripe,
  isPaidBondexSession,
  StripeConfigurationError,
} from '@/lib/stripe';

export const metadata: Metadata = {
  title: 'Payment status — Bondex Notch',
  description: 'Your Bondex Notch Stripe payment status.',
  robots: { index: false, follow: false, noarchive: true },
};

export const dynamic = 'force-dynamic';

type SuccessPageProps = {
  searchParams: Promise<{ session_id?: string }>;
};

export default async function CheckoutSuccess({ searchParams }: SuccessPageProps) {
  const { session_id: sessionId } = await searchParams;
  let paid = false;
  let email: string | null = null;
  let reference: string | null = null;
  let licenseKey: string | null = null;
  let unavailable = false;

  if (sessionId?.startsWith('cs_')) {
    try {
      const session = await getStripe().checkout.sessions.retrieve(sessionId);
      paid = isPaidBondexSession(session);
      email = session.customer_details?.email || session.customer_email;
      reference = session.id.slice(-12).toUpperCase();
      if (paid) {
        licenseKey = session.metadata?.license_key || generateLicenseKey(session.id);
      }
    } catch (error) {
      unavailable = error instanceof StripeConfigurationError;
    }
  }

  return (
    <main id="main" className="checkout-result-page">
      <div className="wrap checkout-result-card">
        <BrandMark />
        <p className="label">Stripe payment</p>
        <h1>{paid ? 'Payment confirmed!' : 'We could not confirm that payment.'}</h1>
        {paid ? (
          <>
            <p>
              Thank you for purchasing Bondex Notch! Your lifetime licence has been issued below.
            </p>

            {licenseKey && <CopyLicenseKey licenseKey={licenseKey} />}

            <div style={{
              textAlign: 'left',
              margin: '24px auto',
              maxWidth: '460px',
              fontSize: '13.5px',
              lineHeight: '1.6',
              background: 'rgba(255, 255, 255, 0.03)',
              borderRadius: '8px',
              padding: '16px 20px',
              border: '1px solid rgba(255, 255, 255, 0.08)'
            }}>
              <p style={{ margin: '0 0 8px 0', fontWeight: 600 }}>How to activate your licence:</p>
              <ol style={{ paddingLeft: '20px', margin: 0 }}>
                <li>Copy the licence key above.</li>
                <li>Open Bondex Notch → click menu bar or notch → <strong>Settings</strong> → <strong>Licence</strong>.</li>
                <li>Paste the key and choose <strong>Apply</strong>.</li>
              </ol>
            </div>

            <dl className="checkout-result-details">
              {email && <><dt>Receipt email</dt><dd>{email}</dd></>}
              {reference && <><dt>Order reference</dt><dd>{reference}</dd></>}
              <dt>Status</dt><dd>Paid</dd>
            </dl>

            <div className="actions actions--center" style={{ marginTop: '24px' }}>
              <a className="btn" href="/download/">
                Download Bondex Notch (.dmg)
              </a>
              <Link className="btn btn--ghost" href="/">Return home</Link>
            </div>
          </>
        ) : (
          <>
            <p>
              {unavailable
                ? 'Checkout configuration is not available yet.'
                : 'The session may be incomplete, expired, or invalid. Check your Stripe receipt before trying again.'}
            </p>
            <div className="actions actions--center">
              <Link className="btn" href="/">Return home</Link>
              <a
                className="btn btn--ghost"
                href={supportMailto('Bondex Notch payment support')}
              >
                Payment support
              </a>
            </div>
          </>
        )}
      </div>
    </main>
  );
}
