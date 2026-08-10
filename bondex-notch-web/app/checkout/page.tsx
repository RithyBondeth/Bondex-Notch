import type { Metadata } from 'next';
import CheckoutPage from '@/components/CheckoutPage';
import { isStripeConfigured } from '@/lib/stripe';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Checkout — Bondex Notch',
  description: 'Review a one-time lifetime Bondex Notch licence purchase.',
  alternates: { canonical: '/checkout/' },
  robots: {
    index: false,
    follow: false,
    noarchive: true,
    googleBot: {
      index: false,
      follow: false,
      noimageindex: true,
    },
  },
};

export default function Checkout() {
  return <CheckoutPage stripeConfigured={isStripeConfigured()} />;
}
