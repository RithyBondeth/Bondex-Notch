'use client';

import { useEffect, useState } from 'react';

const links = [
  { href: '#features', label: 'Features' },
  { href: '#how', label: 'States' },
  { href: '#pricing', label: 'Pricing' },
  { href: '#faq', label: 'FAQ' },
];

/**
 * The navigation is the product: a notch hanging off the top edge of the
 * viewport, fillets and all. It collapses as you scroll, the way the panel
 * collapses when you move the pointer away.
 */
export default function NotchBar() {
  const [stuck, setStuck] = useState(false);

  useEffect(() => {
    const onScroll = () => setStuck(window.scrollY > 24);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <header className={`notchbar${stuck ? ' is-stuck' : ''}`}>
      <div className="notchbar__body">
        <a className="brand" href="#main" aria-label="Bondex Notch home">
          <span className="brand__mark" aria-hidden="true" />
          <span className="brand__name">Bondex&nbsp;Notch</span>
        </a>
        <span className="notchbar__lens" aria-hidden="true" />
        <nav className="notchbar__links" aria-label="Primary">
          {links.map(({ href, label }) => (
            <a key={href} href={href}>
              {label}
            </a>
          ))}
        </nav>
        <a className="btn btn--small" href="#download">
          Download
        </a>
      </div>
    </header>
  );
}
