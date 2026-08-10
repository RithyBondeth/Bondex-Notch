export {};

declare global {
  namespace NodeJS {
    interface ProcessEnv {
      NEXT_PUBLIC_SITE_URL?: string;
      NEXT_PUBLIC_SUPPORT_EMAIL?: string;
      STRIPE_SECRET_KEY?: string;
      STRIPE_WEBHOOK_SECRET?: string;
      STRIPE_PRICE_ID?: string;
      STRIPE_AUTOMATIC_TAX?: 'true' | 'false';
    }
  }
}
