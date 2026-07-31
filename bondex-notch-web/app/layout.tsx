import type { Metadata, Viewport } from 'next';
import { Archivo, DM_Sans, JetBrains_Mono } from 'next/font/google';
import Footer from '@/components/Footer';
import NotchBar from '@/components/NotchBar';
import RibbonField from '@/components/RibbonField';
import { FIELD_BACKDROP } from '@/lib/ribbonField';
import './globals.css';

/* Self-hosted at build time, so there is no third-party round trip and no
   layout shift. Archivo carries the width axis the headline animates on. */

const archivo = Archivo({
  subsets: ['latin'],
  axes: ['wdth'],
  variable: '--font-display',
  display: 'swap',
});

const dmSans = DM_Sans({
  subsets: ['latin'],
  axes: ['opsz'],
  variable: '--font-body',
  display: 'swap',
});

const jetBrainsMono = JetBrains_Mono({
  subsets: ['latin'],
  variable: '--font-mono',
  display: 'swap',
});

const title = "Bondex Notch — Your Mac's notch, finally useful";
const description =
  'A native macOS utility that turns the notch into a live view of your ' +
  'music, downloads, system status and files. Built in Swift. No Electron, ' +
  'no web view.';

export const metadata: Metadata = {
  title,
  description,
  openGraph: {
    type: 'website',
    title,
    description:
      'A native macOS utility that turns the notch into a live view of your ' +
      'music, downloads, system status and files.',
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
      className={`${archivo.variable} ${dmSans.variable} ${jetBrainsMono.variable}`}
    >
      <body>
        <a className="skip-link" href="#main">
          Skip to content
        </a>
        <RibbonField />
        <NotchBar />
        {children}
        <Footer />
      </body>
    </html>
  );
}
