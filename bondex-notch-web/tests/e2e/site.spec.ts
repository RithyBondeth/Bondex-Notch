import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

type HeaderDefinition = { key: string; value: string };

const vercelConfig = JSON.parse(
  readFileSync(resolve(process.cwd(), 'vercel.json'), 'utf8'),
) as {
  headers?: Array<{ source: string; headers: HeaderDefinition[] }>;
};

const globalHeaders = vercelConfig.headers?.find(
  ({ source }) => source === '/(.*)',
)?.headers;

const securityHeaders = new Map(
  globalHeaders?.map(({ key, value }) => [key.toLowerCase(), value]),
);

test('environment templates cover web secrets and app build configuration', () => {
  const webEnvironment = readFileSync(resolve(process.cwd(), '.env.example'), 'utf8');
  for (const name of [
    'NEXT_PUBLIC_SITE_URL',
    'NEXT_PUBLIC_SUPPORT_EMAIL',
    'STRIPE_SECRET_KEY',
    'STRIPE_WEBHOOK_SECRET',
    'STRIPE_PRICE_ID',
    'STRIPE_AUTOMATIC_TAX',
  ]) {
    expect(webEnvironment).toContain(`${name}=`);
  }

  const appEnvironment = readFileSync(
    resolve(process.cwd(), '../bondex-notch-app/.env.example'),
    'utf8',
  );
  expect(appEnvironment).toContain('BONDEX_CHECKOUT_URL=');
  expect(appEnvironment).toContain('DEVELOPER_DIR=');
});

test('Vercel applies the required security headers to every route', () => {
  expect(securityHeaders.get('x-content-type-options')).toBe('nosniff');
  expect(securityHeaders.get('referrer-policy')).toBe(
    'strict-origin-when-cross-origin',
  );
  expect(securityHeaders.get('permissions-policy')).toContain('camera=()');
  expect(securityHeaders.get('permissions-policy')).toContain('microphone=()');
  expect(securityHeaders.get('permissions-policy')).toContain('payment=()');

  const csp = securityHeaders.get('content-security-policy');
  expect(csp).toContain("default-src 'self'");
  expect(csp).toContain("object-src 'none'");
  expect(csp).toContain("frame-ancestors 'none'");
  expect(csp).toContain("base-uri 'self'");
  expect(csp).toContain("form-action 'self'");
  expect(csp).not.toContain("'unsafe-eval'");
});

test('landing page exposes the release and policy paths', async ({ page }) => {
  await page.goto('/');

  await expect(page).toHaveTitle(/Bondex Notch/);
  await expect(page.getByRole('heading', { level: 1 })).toContainText(
    "Your Mac's notch",
  );

  const footer = page.locator('footer.footer');
  await expect(footer.getByRole('link', { name: 'Privacy' }).first()).toHaveAttribute(
    'href',
    '/privacy/',
  );
  await expect(footer.getByRole('link', { name: 'Terms' }).first()).toHaveAttribute(
    'href',
    '/terms/',
  );
  await expect(footer.getByRole('link', { name: 'Refunds' })).toHaveAttribute(
    'href',
    '/refunds/',
  );
  await expect(footer.getByRole('link', { name: 'Licence support' })).toHaveAttribute(
    'href',
    '/license-support/',
  );
});

const policyRoutes = [
  { path: '/privacy/', title: 'Privacy Policy' },
  { path: '/terms/', title: 'Terms of Use' },
  { path: '/refunds/', title: 'Refund Policy' },
  { path: '/license-support/', title: 'Licence Support' },
];

for (const route of policyRoutes) {
  test(`${route.title} is published with canonical metadata`, async ({ page }) => {
    await page.goto(route.path);

    await expect(page.getByRole('heading', { level: 1 })).toHaveText(route.title);
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
      'href',
      `https://bondex-notch.bondeth.site${route.path}`,
    );
    await expect(page.locator('.legal-sidebar nav a')).toHaveCount(4);
    await expect(page.locator('.legal-article section').first()).toBeVisible();
  });
}

test('checkout delegates card collection to Stripe', async ({ page }) => {
  await page.goto('/checkout/');
  await expect(page.getByRole('heading', { name: "Pay on Stripe's secure page." })).toBeVisible();
  await expect(page.getByLabel('Card number')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Checkout setup in progress' })).toBeDisabled();
  await expect(page.getByText('Bondex never receives or stores your card number.')).toBeVisible();
});

test('checkout API fails closed when Stripe secrets are absent', async ({ request }) => {
  const response = await request.post('/api/stripe/checkout');
  expect(response.status()).toBe(503);
  expect(response.headers()['cache-control']).toBe('no-store');
  await expect(response.json()).resolves.toEqual({
    error: 'Checkout is being configured. Please try again later.',
  });
});

test('checkout API rejects cross-origin session creation', async ({ request }) => {
  const response = await request.post('/api/stripe/checkout', {
    headers: { Origin: 'https://attacker.example' },
  });
  expect(response.status()).toBe(403);
});

test('webhook fails closed when its signing secret is absent', async ({ request }) => {
  const response = await request.post('/api/stripe/webhook', {
    data: '{}',
    headers: { 'Stripe-Signature': 'invalid' },
  });
  expect(response.status()).toBe(503);
});

test('success page does not trust an invalid session identifier', async ({ page }) => {
  await page.goto('/checkout/success/?session_id=not-a-session');
  await expect(
    page.getByRole('heading', { name: 'We could not confirm that payment.' }),
  ).toBeVisible();
});

test('legal pages do not overflow a phone viewport', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/privacy/');

  const dimensions = await page.evaluate(() => ({
    viewport: document.documentElement.clientWidth,
    content: document.documentElement.scrollWidth,
  }));

  expect(dimensions.content).toBeLessThanOrEqual(dimensions.viewport);
  await expect(page.locator('.legal-sidebar nav')).toBeVisible();
});
