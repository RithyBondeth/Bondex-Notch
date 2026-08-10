import { randomUUID } from 'node:crypto';
import { NextResponse } from 'next/server';
import {
  assertBondexPrice,
  buildCheckoutSessionParams,
  getStripe,
  isStripeConfigured,
  StripeConfigurationError,
} from '@/lib/stripe';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

function validIdempotencyKey(value: string | null) {
  return value && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    ? value
    : randomUUID();
}

export async function POST(request: Request) {
  try {
    const origin = request.headers.get('origin');
    if (origin && origin !== new URL(request.url).origin) {
      return NextResponse.json(
        { error: 'Cross-origin checkout requests are not allowed.' },
        { status: 403, headers: { 'Cache-Control': 'no-store' } },
      );
    }

    if (!isStripeConfigured()) throw new StripeConfigurationError();
    const stripe = getStripe();
    await assertBondexPrice(stripe);
    const session = await stripe.checkout.sessions.create(
      buildCheckoutSessionParams(),
      { idempotencyKey: validIdempotencyKey(request.headers.get('idempotency-key')) },
    );

    if (!session.url) {
      return NextResponse.json(
        { error: 'Stripe did not return a checkout URL.' },
        { status: 502, headers: { 'Cache-Control': 'no-store' } },
      );
    }

    return NextResponse.json(
      { url: session.url },
      { headers: { 'Cache-Control': 'no-store' } },
    );
  } catch (error) {
    if (error instanceof StripeConfigurationError) {
      return NextResponse.json(
        { error: 'Checkout is being configured. Please try again later.' },
        { status: 503, headers: { 'Cache-Control': 'no-store' } },
      );
    }

    console.error('Unable to create Stripe Checkout Session', error);
    return NextResponse.json(
      { error: 'Unable to start secure checkout. Please try again.' },
      { status: 500, headers: { 'Cache-Control': 'no-store' } },
    );
  }
}
