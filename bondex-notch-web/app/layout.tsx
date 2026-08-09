import type { Metadata, Viewport } from 'next';
import { Ubuntu, Ubuntu_Mono } from 'next/font/google';
import Footer from '@/components/Footer';
import MotionEffects from '@/components/MotionEffects';
import NotchBar from '@/components/NotchBar';
import RibbonField from '@/components/RibbonField';
import { FIELD_BACKDROP } from '@/lib/ribbonField';
import { SITE_DESCRIPTION, SITE_NAME, SITE_TITLE, SITE_URL } from '@/lib/seo';
import './globals.css';

/* Self-hosted at build time, so there is no third-party round trip or layout
   shift. Ubuntu is the shared display and body face; Ubuntu Mono keeps the
   compact technical labels aligned with the same family. */

const ubuntu = Ubuntu({
  subsets: ['latin'],
  weight: ['300', '400', '500', '700'],
  variable: '--font-ubuntu',
  display: 'swap',
});

const ubuntuMono = Ubuntu_Mono({
  subsets: ['latin'],
  weight: ['400', '700'],
  variable: '--font-ubuntu-mono',
  display: 'swap',
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  applicationName: SITE_NAME,
  title: SITE_TITLE,
  description: SITE_DESCRIPTION,
  alternates: { canonical: '/' },
  authors: [{ name: 'Rithy Bondeth', url: SITE_URL }],
  creator: 'Rithy Bondeth',
  publisher: SITE_NAME,
  category: 'technology',
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-image-preview': 'large',
      'max-snippet': -1,
      'max-video-preview': -1,
    },
  },
  openGraph: {
    type: 'website',
    url: '/',
    siteName: SITE_NAME,
    locale: 'en_US',
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    images: [{
      url: '/og.jpg',
      width: 1200,
      height: 630,
      type: 'image/jpeg',
      alt: 'Bondex Notch on a Mac display',
    }],
  },
  twitter: {
    card: 'summary_large_image',
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    images: ['/og.jpg'],
  },
};

export const viewport: Viewport = {
  themeColor: FIELD_BACKDROP,
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      className={`${ubuntu.variable} ${ubuntuMono.variable}`}
    >
      <body>
        <a className="skip-link" href="#main">
          Skip to content
        </a>
        <RibbonField />
        <MotionEffects />
        <NotchBar />
        {children}
        <Footer />
      </body>
    </html>
  );
}
