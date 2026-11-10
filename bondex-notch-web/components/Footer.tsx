import Image from 'next/image';
import Link from 'next/link';
import BrandMark from '@/components/BrandMark';
import { contacts } from '@/content/contact';

export default function Footer() {

  return (
    <footer className="footer">
      <div className="wrap footer__inner">
        <div className="footer__intro">
          <span className="brand">
            <BrandMark />
            <span className="brand__name">Bondex&nbsp;Notch</span>
          </span>
          <p>
            A calmer control center for macOS, built privately in Cambodia.
            Questions, bug reports, and feedback are always welcome.
          </p>
          <span className="footer__availability"><i /> Available for direct messages</span>
        </div>

        <nav className="footer__nav" aria-label="Footer navigation">
          <b>Explore</b>
          {/* Rooted at /, so they work from every page, not only the home page. */}
          <Link href="/#showcase">Product tour</Link>
          <Link href="/#efficiency">Performance</Link>
          <Link href="/#features">Features</Link>
          <Link href="/#pricing">Open source</Link>
          <Link href="/#faq">FAQ</Link>
          <Link href="/about/">About the developer</Link>
          <b className="footer__nav-subtitle">Legal &amp; support</b>
          <Link href="/privacy/">Privacy</Link>
          <Link href="/terms/">Terms</Link>
          <a href="https://github.com/RithyBondeth/Bondex-Notch">Source code</a>
        </nav>

        <div className="footer__contacts">
          <div className="footer__contacts-head">
            <b>Contact directly</b>
            <span>Choose what works for you</span>
          </div>
          <div className="footer__contact-grid">
            {contacts.map(({ service, icon, label, value, href }) => (
              <a
                href={href}
                className="footer__contact-card"
                data-service={service}
                target={service === 'email' ? undefined : '_blank'}
                rel={service === 'email' ? undefined : 'noreferrer'}
                key={service}
              >
                <span className="footer__contact-mark" aria-hidden="true">
                  <Image src={icon} alt="" width={18} height={18} />
                </span>
                <span>
                  <b>{label}</b>
                  <small>{value}</small>
                </span>
                <i aria-hidden="true">↗</i>
              </a>
            ))}
          </div>
        </div>
      </div>

      <div className="wrap footer__bottom">
        <p className="footer__legal">© 2026 Bondex Notch · Built with Swift and SwiftUI.</p>
        <p className="footer__legal">
          <Link href="/privacy/">Privacy</Link> · <Link href="/terms/">Terms</Link> · Not affiliated with Apple Inc.
        </p>
      </div>
    </footer>
  );
}
