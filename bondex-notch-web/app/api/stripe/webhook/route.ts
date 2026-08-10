import { NextResponse } from 'next/server';
import type Stripe from 'stripe';
import {
  getStripe,
  isPaidBondexSession,
  StripeConfigurationError,
} from '@/lib/stripe';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const paidEvents = new Set([
  'checkout.session.completed',
  'checkout.session.async_payment_succeeded',
]);

async function markPaymentVerified(session: Stripe.Checkout.Session) {
  if (!isPaidBondexSession(session)) return;
  if (session.metadata?.fulfilment === 'payment_verified') return;

  const stripe = getStripe();
  await stripe.checkout.sessions.update(session.id, {
    metadata: {
      ...session.metadata,
      fulfilment: 'payment_verified',
    },
  });
}

export async function POST(request: Request) {
  try {
    const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
    const signature = request.headers.get('stripe-signature');
    if (!webhookSecret) throw new StripeConfigurationError('Stripe webhook is not configured.');
    if (!signature) {
      return NextResponse.json({ error: 'Missing Stripe signature.' }, { status: 400 });
    }

    const stripe = getStripe();
    const rawBody = await request.text();
    let event: Stripe.Event;

    try {
      event = stripe.webhooks.constructEvent(rawBody, signature, webhookSecret);
    } catch {
      return NextResponse.json({ error: 'Invalid Stripe signature.' }, { status: 400 });
    }

    if (paidEvents.has(event.type)) {
      await markPaymentVerified(event.data.object as Stripe.Checkout.Session);
    }

    return NextResponse.json({ received: true });
  } catch (error) {
    if (error instanceof StripeConfigurationError) {
      return NextResponse.json({ error: error.message }, { status: 503 });
    }
    console.error('Stripe webhook processing failed', error);
    return NextResponse.json({ error: 'Webhook processing failed.' }, { status: 500 });
  }
}
