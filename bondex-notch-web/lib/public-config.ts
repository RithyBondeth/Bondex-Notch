const defaultSiteUrl = 'https://bondex-notch.bondeth.site';
const defaultSupportEmail = 'rithybondeth999@gmail.com';

function normaliseSiteUrl(value: string | undefined) {
  if (!value) return defaultSiteUrl;
  try {
    const url = new URL(value);
    if (!['http:', 'https:'].includes(url.protocol)) throw new Error('Unsupported protocol');
    return url.origin;
  } catch {
    throw new Error('NEXT_PUBLIC_SITE_URL must be an absolute http:// or https:// URL.');
  }
}

export const SITE_URL = normaliseSiteUrl(process.env.NEXT_PUBLIC_SITE_URL);
const configuredSupportEmail = process.env.NEXT_PUBLIC_SUPPORT_EMAIL?.trim();
if (configuredSupportEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(configuredSupportEmail)) {
  throw new Error('NEXT_PUBLIC_SUPPORT_EMAIL must be a valid email address.');
}
export const SUPPORT_EMAIL = configuredSupportEmail || defaultSupportEmail;

export function supportMailto(subject: string) {
  return `mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent(subject)}`;
}
