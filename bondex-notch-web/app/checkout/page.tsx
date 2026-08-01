import type { Metadata } from 'next';
import CheckoutPage from '@/components/CheckoutPage';

export const metadata: Metadata = {
  title: 'Checkout — Bondex Notch Pro',
  description: 'Review a one-time Bondex Notch Pro license purchase.',
};

export default function Checkout() {
  return <CheckoutPage />;
}
