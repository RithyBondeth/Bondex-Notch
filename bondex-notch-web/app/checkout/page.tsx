import type { Metadata } from 'next';
import CheckoutPage from '@/components/CheckoutPage';

export const metadata: Metadata = {
  title: 'Checkout — Bondex Notch Pro',
  description: 'Review a one-time Bondex Notch Pro license purchase.',
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
  return <CheckoutPage />;
}
