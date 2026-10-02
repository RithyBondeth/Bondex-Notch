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

test('environment templates cover web and app build configuration', () => {
  const webEnvironment = readFileSync(resolve(process.cwd(), '.env.example'), 'utf8');
  for (const name of ['NEXT_PUBLIC_SITE_URL', 'NEXT_PUBLIC_SUPPORT_EMAIL']) {
    expect(webEnvironment).toContain(`${name}=`);
  }
  expect(webEnvironment).not.toContain('STRIPE_');

  const appEnvironment = readFileSync(
    resolve(process.cwd(), '../bondex-notch-app/.env.example'),
    'utf8',
  );
  expect(appEnvironment).not.toContain('BONDEX_CHECKOUT_URL');
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
  await expect(footer.getByRole('link', { name: 'Source code' })).toHaveAttribute(
    'href',
    'https://github.com/RithyBondeth/Bondex-Notch',
  );
  await expect(page.getByRole('link', { name: 'Download for Mac' }).first()).toHaveAttribute(
    'href',
    '/download/',
  );
  await expect(page.getByText('$14.99')).toHaveCount(0);
});

const policyRoutes = [
  { path: '/privacy/', title: 'Privacy Policy' },
  { path: '/terms/', title: 'Terms of Use' },
];

for (const route of policyRoutes) {
  test(`${route.title} is published with canonical metadata`, async ({ page }) => {
    await page.goto(route.path);

    await expect(page.getByRole('heading', { level: 1 })).toHaveText(route.title);
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
      'href',
      `https://bondex-notch.bondeth.site${route.path}`,
    );
    await expect(page.locator('.legal-sidebar nav a')).toHaveCount(2);
    await expect(page.locator('.legal-article section').first()).toBeVisible();
  });
}

test('paid checkout routes are gone', async ({ request }) => {
  for (const path of ['/checkout/', '/refunds/', '/license-support/']) {
    const response = await request.get(path);
    expect(response.status(), path).toBe(404);
  }
  const api = await request.post('/api/stripe/checkout');
  expect(api.status()).toBe(404);
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
