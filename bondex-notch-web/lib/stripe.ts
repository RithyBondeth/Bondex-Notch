import 'server-only';
import Stripe from 'stripe';
import { SITE_URL } from '@/lib/public-config';

export const BONDEX_PRICE_CENTS = 1499;
export const BONDEX_PRODUCT_NAME = 'Bondex Notch — Lifetime licence';

let stripeClient: Stripe | undefined;
let verifiedPriceId: string | undefined;

export class StripeConfigurationError extends Error {
  constructor(message = 'Stripe checkout is not configured.') {
    super(message);
    this.name = 'StripeConfigurationError';
  }
}

export function isStripeConfigured() {
  return Boolean(
    /^sk_(test|live)_/.test(process.env.STRIPE_SECRET_KEY || '') &&
      /^price_/.test(process.env.STRIPE_PRICE_ID || '') &&
      /^whsec_/.test(process.env.STRIPE_WEBHOOK_SECRET || ''),
  );
}

export function getStripe() {
  const secretKey = process.env.STRIPE_SECRET_KEY;
  if (!secretKey || !/^sk_(test|live)_/.test(secretKey)) {
    throw new StripeConfigurationError();
  }
  stripeClient ??= new Stripe(secretKey);
  return stripeClient;
}

export function buildCheckoutSessionParams(): Stripe.Checkout.SessionCreateParams {
  const priceId = process.env.STRIPE_PRICE_ID;
  if (!priceId) throw new StripeConfigurationError();

  const taxSetting = process.env.STRIPE_AUTOMATIC_TAX || 'false';
  if (!['true', 'false'].includes(taxSetting)) {
    throw new StripeConfigurationError('STRIPE_AUTOMATIC_TAX must be true or false.');
  }
  const automaticTax = taxSetting === 'true';

  return {
    mode: 'payment',
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: `${SITE_URL}/checkout/success/?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${SITE_URL}/checkout/?cancelled=1`,
    customer_creation: 'always',
    billing_address_collection: 'auto',
    allow_promotion_codes: false,
    automatic_tax: { enabled: automaticTax },
    consent_collection: { terms_of_service: 'required' },
    metadata: {
      product: 'bondex-notch',
      licence: 'lifetime',
      fulfilment: 'pending',
    },
    payment_intent_data: {
      description: BONDEX_PRODUCT_NAME,
      metadata: {
        product: 'bondex-notch',
        licence: 'lifetime',
      },
    },
  };
}

export async function assertBondexPrice(stripe: Stripe) {
  const priceId = process.env.STRIPE_PRICE_ID;
  if (!priceId) throw new StripeConfigurationError();
  if (verifiedPriceId === priceId) return;

  try {
    const price = await stripe.prices.retrieve(priceId);
    const valid =
      price.active &&
      price.currency === 'usd' &&
      price.unit_amount === BONDEX_PRICE_CENTS &&
      price.type === 'one_time';

    if (!valid) {
      throw new StripeConfigurationError(
        'Stripe Price must be an active, one-time USD 14.99 price.',
      );
    }
  } catch (error) {
    if (error instanceof StripeConfigurationError) throw error;
    throw new StripeConfigurationError('Unable to verify the configured Stripe Price.');
  }

  verifiedPriceId = priceId;
}

export function isPaidBondexSession(session: Stripe.Checkout.Session) {
  const paymentComplete =
    session.payment_status === 'paid' ||
    session.payment_status === 'no_payment_required';

  return (
    paymentComplete &&
    session.currency === 'usd' &&
    session.amount_subtotal === BONDEX_PRICE_CENTS &&
    session.metadata?.product === 'bondex-notch' &&
    session.metadata?.licence === 'lifetime'
  );
}
