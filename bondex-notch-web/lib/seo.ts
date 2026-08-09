export const SITE_URL = 'https://bondex-notch.bondeth.site';
export const SITE_NAME = 'Bondex Notch';
export const SITE_TITLE = "Bondex Notch — Your Mac's notch, finally useful";
export const SITE_DESCRIPTION =
  'Bondex Notch is a native macOS utility for music, focus, meetings, captures, ' +
  'coding agents, files and system status—all inside your Mac’s notch.';

export const websiteJsonLd = {
  '@context': 'https://schema.org',
  '@type': 'WebSite',
  name: SITE_NAME,
  url: SITE_URL,
  description: SITE_DESCRIPTION,
  inLanguage: 'en',
};

export const softwareApplicationJsonLd = {
  '@context': 'https://schema.org',
  '@type': 'SoftwareApplication',
  name: SITE_NAME,
  applicationCategory: 'UtilitiesApplication',
  operatingSystem: 'macOS 14 or later',
  description: SITE_DESCRIPTION,
  url: SITE_URL,
  image: `${SITE_URL}/og.jpg`,
  screenshot: [
    `${SITE_URL}/app-previews/productivity.png`,
    `${SITE_URL}/app-previews/music.png`,
    `${SITE_URL}/app-previews/system.png`,
  ],
  offers: {
    '@type': 'Offer',
    price: '14.99',
    priceCurrency: 'USD',
    description: 'One-time lifetime licence after a full 24-hour trial',
    url: `${SITE_URL}/#pricing`,
  },
  featureList: [
    'Music and browser playback controls',
    'Coding agent activity',
    'Quick Capture and clipboard history',
    'Focus timer and upcoming meetings',
    'Smart profiles and custom live activities',
    'System metrics, file activity and drop shelf',
  ],
};

/** Keep structured data safe if any future copy contains HTML-like text. */
export function serializeJsonLd(value: unknown) {
  return JSON.stringify(value).replace(/</g, '\\u003c');
}
