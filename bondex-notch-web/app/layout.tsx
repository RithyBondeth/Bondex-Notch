import type { Metadata, Viewport } from 'next';
import { Ubuntu, Ubuntu_Mono } from 'next/font/google';
import Footer from '@/components/Footer';
import MotionEffects from '@/components/MotionEffects';
import NotchBar from '@/components/NotchBar';
import RibbonField from '@/components/RibbonField';
import { FIELD_BACKDROP } from '@/lib/ribbonField';
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

const title = "Bondex Notch — Your Mac's notch, finally useful";
const description =
  'A native macOS utility that turns the notch into a live view of your ' +
  'captures, focus sessions, meetings, music, coding agents, live tasks and system status. ' +
  'Built in Swift. No Electron, no web view.';

export const metadata: Metadata = {
  metadataBase: new URL('https://bondex-notch.bondeth-plus1.chatgpt.site'),
  title,
  description,
  openGraph: {
    type: 'website',
    title,
    description:
      'A native macOS utility that turns the notch into a live view of your ' +
      'captures, focus sessions, meetings, music, agents and system status.',
    images: [{ url: '/og.png', width: 1200, height: 630, alt: 'Bondex Notch on a Mac display' }],
  },
  twitter: {
    card: 'summary_large_image',
    title,
    description,
    images: ['/og.png'],
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
