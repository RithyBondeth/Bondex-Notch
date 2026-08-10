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

test('checkout validates locally without sending a payment request', async ({ page }) => {
  const nonReadRequests: string[] = [];
  page.on('request', (request) => {
    if (!['GET', 'HEAD'].includes(request.method())) {
      nonReadRequests.push(`${request.method()} ${request.url()}`);
    }
  });

  await page.goto('/checkout/');
  await page
    .getByRole('textbox', { name: 'Card number', exact: true })
    .fill('4242 4242 4242 4242');
  await page.getByLabel('Name on card').fill('Bondex Tester');
  await page.getByLabel('Expiration month').selectOption('12');

  const yearSelect = page.getByLabel('Expiration year');
  const lastYear = await yearSelect.locator('option').last().getAttribute('value');
  expect(lastYear).toBeTruthy();
  await yearSelect.selectOption(lastYear!);
  await page.getByLabel('Security code').fill('123');

  const submit = page.getByRole('button', { name: 'Review $14.99 payment' });
  await expect(submit).toBeEnabled();
  await submit.click();

  await expect(page.getByRole('status')).toContainText('Payment details look valid');
  expect(nonReadRequests).toEqual([]);
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
