import type { Metadata } from 'next';
import Link from 'next/link';
import BrandMark from '@/components/BrandMark';
import { supportMailto } from '@/lib/public-config';
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
  let unavailable = false;

  if (sessionId?.startsWith('cs_')) {
    try {
      const session = await getStripe().checkout.sessions.retrieve(sessionId);
      paid = isPaidBondexSession(session);
      email = session.customer_details?.email || session.customer_email;
      reference = session.id.slice(-12).toUpperCase();
    } catch (error) {
      unavailable = error instanceof StripeConfigurationError;
    }
  }

  return (
    <main id="main" className="checkout-result-page">
      <div className="wrap checkout-result-card">
        <BrandMark />
        <p className="label">Stripe payment</p>
        <h1>{paid ? 'Payment confirmed.' : 'We could not confirm that payment.'}</h1>
        {paid ? (
          <>
            <p>
              Thank you for purchasing Bondex Notch. Keep your Stripe receipt and
              the order reference below for licence support.
            </p>
            <dl className="checkout-result-details">
              {email && <><dt>Receipt email</dt><dd>{email}</dd></>}
              {reference && <><dt>Order reference</dt><dd>{reference}</dd></>}
              <dt>Status</dt><dd>Paid</dd>
            </dl>
          </>
        ) : (
          <p>
            {unavailable
              ? 'Checkout configuration is not available yet.'
              : 'The session may be incomplete, expired, or invalid. Check your Stripe receipt before trying again.'}
          </p>
        )}
        <div className="actions actions--center">
          <Link className="btn" href="/">Return home</Link>
          <a
            className="btn btn--ghost"
            href={supportMailto('Bondex Notch payment support')}
          >
            Payment support
          </a>
        </div>
      </div>
    </main>
  );
}
