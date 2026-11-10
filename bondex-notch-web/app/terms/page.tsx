import type { Metadata } from 'next';
import LegalPage from '@/components/LegalPage';
import { GITHUB_REPO_URL, SUPPORT_EMAIL, supportMailto } from '@/lib/public-config';

export const metadata: Metadata = {
  title: 'Terms of Use — Bondex Notch',
  description: 'Terms for the Bondex Notch website and the MIT-licensed software.',
  alternates: { canonical: '/terms/' },
};

export default function TermsPage() {
  return (
    <LegalPage
      currentPath="/terms/"
      eyebrow="Free and open source"
      title="Terms of Use"
      intro="Bondex Notch is free, open-source software released under the MIT License. These terms cover the website and summarise how the software licence applies."
    >
      <section>
        <h2>1. Operator</h2>
        <p>
          Bondex Notch is independently developed and operated by Rithy Bondeth
          in Cambodia. Questions can be sent to{' '}
          <a href={supportMailto('Bondex Notch terms')}>
            {SUPPORT_EMAIL}
          </a>
          .
        </p>
      </section>

      <section className="legal-callout">
        <h2>2. Software licence</h2>
        <p>
          The Bondex Notch app and its source code are licensed under the{' '}
          <a href={`${GITHUB_REPO_URL}/blob/main/LICENSE`}>MIT License</a>. You
          may use, copy, modify, merge, publish, distribute, sublicense, and sell
          copies of the software, provided the copyright notice and licence text
          are included. If anything on this page conflicts with the MIT License,
          the MIT License governs the software.
        </p>
        <p>
          The software is free. There is no trial, account, or licence key, and
          every feature is available to everyone.
        </p>
      </section>

      <section>
        <h2>3. Name and branding</h2>
        <p>
          The MIT License covers the code, not the Bondex Notch name or logo. If
          you distribute a modified version, please give it a different name so
          people are not confused about which build they are running.
        </p>
      </section>

      <section>
        <h2>4. Third-party services</h2>
        <p>
          Bondex works with macOS and third-party apps such as media players,
          browsers, calendars, coding agents, and communication tools. Their
          availability, interfaces, and terms are outside our control. You are
          responsible for using those services lawfully.
        </p>
      </section>

      <section>
        <h2>5. No warranty</h2>
        <p>
          As stated in the MIT License, the software is provided “as is”, without
          warranty of any kind, and its authors are not liable for any claim,
          damages, or other liability arising from it or its use. The website is
          provided on the same basis to the extent permitted by law. Nothing here
          excludes rights that cannot legally be excluded.
        </p>
      </section>

      <section>
        <h2>6. Changes</h2>
        <p>
          We may update these terms when the website or project changes. Material
          changes apply prospectively and will be identified by a new effective
          date.
        </p>
      </section>
    </LegalPage>
  );
}
