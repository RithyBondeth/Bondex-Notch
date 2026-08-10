import Link from 'next/link';
import type { ReactNode } from 'react';

const legalLinks = [
  { href: '/privacy/', label: 'Privacy' },
  { href: '/terms/', label: 'Terms' },
  { href: '/refunds/', label: 'Refunds' },
  { href: '/license-support/', label: 'Licence support' },
];

type LegalPageProps = {
  currentPath: string;
  eyebrow: string;
  title: string;
  intro: string;
  children: ReactNode;
};

export default function LegalPage({
  currentPath,
  eyebrow,
  title,
  intro,
  children,
}: LegalPageProps) {
  return (
    <main id="main" className="legal-page">
      <header className="legal-hero">
        <div className="wrap wrap--narrow">
          <p className="label label--light">{eyebrow}</p>
          <h1>{title}</h1>
          <p>{intro}</p>
          <span>Effective 10 August 2026 · Last updated 10 August 2026</span>
        </div>
      </header>

      <div className="wrap legal-shell">
        <aside className="legal-sidebar" aria-label="Legal and support pages">
          <b>Legal &amp; support</b>
          <nav>
            {legalLinks.map(({ href, label }) => (
              <Link
                href={href}
                aria-current={currentPath === href ? 'page' : undefined}
                key={href}
              >
                {label}
              </Link>
            ))}
          </nav>
          <p>
            Need a human? Email{' '}
            <a href="mailto:rithybondeth999@gmail.com?subject=Bondex%20Notch%20support">
              Bondex support
            </a>
            .
          </p>
        </aside>

        <article className="legal-article">{children}</article>
      </div>
    </main>
  );
}
