'use client';

import { useState } from 'react';
import Link from 'next/link';
import BrandMark from '@/components/BrandMark';
import {
  CreditCardForm,
  type CardState,
  type CardValidity,
} from '@/components/ui/credit-card-form';

export default function CheckoutPage() {
  const [reviewReady, setReviewReady] = useState(false);

  const handleSubmit = (_state: CardState, validity: CardValidity) => {
    if (validity.allValid) setReviewReady(true);
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
              <span>Payment details</span>
              <span><i aria-hidden="true">◇</i> Local validation</span>
            </div>

            <CreditCardForm
              maskMiddle
              ring1="#3cc1f6"
              ring2="#9a7cff"
              submitLabel="Review $14.99 payment"
              onSubmit={handleSubmit}
            />

            {reviewReady && (
              <div className="checkout-notice" role="status">
                <span aria-hidden="true">✓</span>
                <p>
                  <strong>Payment details look valid.</strong>
                  A payment provider still needs to be connected before this page can charge a card.
                </p>
              </div>
            )}
          </div>
        </div>

        <footer className="checkout-footer">
          <span>Private by design</span>
          <span>One-time license</span>
          <span>Built for macOS 14+</span>
        </footer>
      </div>
    </main>
  );
}
