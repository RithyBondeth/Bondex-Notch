'use client';

import { useState } from 'react';
import Link from 'next/link';
import BrandMark from '@/components/BrandMark';

type CheckoutPageProps = {
  stripeConfigured: boolean;
};

export default function CheckoutPage({ stripeConfigured }: CheckoutPageProps) {
  const [isRedirecting, setIsRedirecting] = useState(false);
  const [error, setError] = useState<string>();

  const startCheckout = async () => {
    if (!stripeConfigured || isRedirecting) return;
    setIsRedirecting(true);
    setError(undefined);

    try {
      const response = await fetch('/api/stripe/checkout', {
        method: 'POST',
        headers: { 'Idempotency-Key': crypto.randomUUID() },
      });
      const data = (await response.json()) as { url?: string; error?: string };
      if (!response.ok || !data.url) {
        throw new Error(data.error || 'Unable to start checkout.');
      }
      window.location.assign(data.url);
    } catch (checkoutError) {
      setError(
        checkoutError instanceof Error
          ? checkoutError.message
          : 'Unable to start checkout.',
      );
      setIsRedirecting(false);
    }
  };

  return (
    <main id="main" className="checkout-page">
      <div className="checkout-orb checkout-orb--one" aria-hidden="true" />
      <div className="checkout-orb checkout-orb--two" aria-hidden="true" />

      <div className="wrap checkout-wrap">
        <header className="checkout-header">
          <Link className="checkout-back" href="/">← Back to Bondex Notch</Link>
          <span className="checkout-step">Secure checkout · One-time license</span>
        </header>

        <section className="checkout-intro">
          <p className="label">Bondex Notch</p>
          <h1>Keep the complete app.</h1>
          <p>
            After your 24-hour trial, one lifetime licence keeps every Bondex
            Notch feature available. There are no Free or Pro tiers.
          </p>
        </section>

        <div className="checkout-layout">
          <aside className="order-card" aria-label="Order summary">
            <div className="order-card__product">
              <BrandMark />
              <span>
                <small>Lifetime license</small>
                <strong>Bondex Notch</strong>
              </span>
              <strong>$14.99</strong>
            </div>

            <ul className="order-card__features">
              <li>The complete app after your 24-hour trial</li>
              <li>Every current feature included</li>
              <li>No feature tiers or recurring app fee</li>
              <li>Use the version you buy forever</li>
            </ul>

            <div className="order-card__total">
              <span>
                <small>Total due</small>
                <strong>One-time payment</strong>
              </span>
              <strong>$14.99</strong>
            </div>

            <p className="order-card__note">
              No subscription, account, or recurring app fee.
            </p>
          </aside>

          <div className="checkout-payment">
            <div className="checkout-payment__heading">
              <span>Secure payment</span>
              <span><i aria-hidden="true">◆</i> Powered by Stripe</span>
            </div>

            <div className="stripe-checkout-card">
              <span className="stripe-checkout-card__mark" aria-hidden="true">S</span>
              <div>
                <p className="label">Stripe Checkout</p>
                <h2>Pay on Stripe&apos;s secure page.</h2>
                <p>
                  Bondex never receives or stores your card number. Stripe handles
                  payment details, authentication, and the payment receipt.
                </p>
              </div>
            </div>

            <ul className="stripe-checkout-facts" aria-label="Checkout details">
              <li><span>Total</span><strong>$14.99 USD</strong></li>
              <li><span>Billing</span><strong>One-time</strong></li>
              <li><span>Access</span><strong>Lifetime licence</strong></li>
            </ul>

            <button
              className="payment-submit stripe-checkout-submit"
              type="button"
              onClick={startCheckout}
              disabled={!stripeConfigured || isRedirecting}
            >
              <span>
                {!stripeConfigured
                  ? 'Checkout setup in progress'
                  : isRedirecting
                    ? 'Opening Stripe…'
                    : 'Continue to Stripe · $14.99'}
              </span>
              <i aria-hidden="true">→</i>
            </button>

            {error && <p className="stripe-checkout-error" role="alert">{error}</p>}

            <p className="payment-form__privacy stripe-checkout-privacy">
              <span aria-hidden="true">◆</span>
              You will review the final amount before paying on Stripe.
            </p>
          </div>
        </div>

        <footer className="checkout-footer">
          <Link href="/privacy/">Privacy</Link>
          <Link href="/terms/">Terms</Link>
          <Link href="/refunds/">Refunds</Link>
          <Link href="/license-support/">Licence support</Link>
        </footer>
      </div>
    </main>
  );
}
