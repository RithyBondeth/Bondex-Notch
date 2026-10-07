import type { Metadata } from 'next';
import Image from 'next/image';
import Link from 'next/link';
import { contacts, GITHUB_PROFILE_URL } from '@/content/contact';
import { GITHUB_REPO_URL } from '@/lib/public-config';

export const metadata: Metadata = {
  title: 'About the developer — Bondex Notch',
  description:
    'Bondex Notch is built by Rithy Bondeth, an independent developer in Phnom Penh, Cambodia. Free, open source and private by design.',
  alternates: { canonical: '/about/' },
};

const principles = [
  {
    title: 'Private by default',
    body:
      'No account and no sign-in. Captures, clipboard history and agent usage stay on your Mac, and the only thing that ever leaves it is the update check — and only if you turn it on.',
  },
  {
    title: 'Light on your Mac',
    body:
      'A native Swift and SwiftUI app with no Electron or web view. Continuous animation runs on Core Animation, and a widget you switch off stops its service entirely.',
  },
  {
    title: 'Honest about macOS',
    body:
      'Where macOS has no API — reading other apps’ notifications, for one — Bondex says so instead of faking it, and uses the supported route everywhere else.',
  },
  {
    title: 'Open to everyone',
    body:
      'Every feature is free under the MIT License. Read the code, build it yourself, or download the ready-made app; every update is verified before it installs.',
  },
];

const releases = [
  {
    version: '1.1.1',
    date: '7 October 2026',
    summary: 'Gemini CLI joins Claude Code and Codex in the notch, and in-app updates work end to end.',
  },
  {
    version: '1.1.0',
    date: '6 October 2026',
    summary:
      'Updates built in, “Needs you” when an agent waits on you, one-click agent setup, a notch that follows your display, and a first-launch welcome.',
  },
  {
    version: '1.0.0',
    date: '2 October 2026',
    summary: 'The first public release: the notch as a live surface for music, agents, files and more.',
  },
];

export default function AboutPage() {
  return (
    <main id="main" className="about-page">
      <div className="wrap">
        <section className="slab about-hero">
          <div className="about-hero__avatar" aria-hidden="true">
            RB
          </div>
          <div>
            <p className="label">About the developer</p>
            <h1 className="title">Rithy Bondeth</h1>
            <p className="lede">
              Bondex Notch is designed and built by Rithy Bondeth, an independent
              developer in Phnom Penh, Cambodia — in the open, and free for everyone.
            </p>
            <ul className="about-hero__facts" aria-label="At a glance">
              <li>Phnom Penh, Cambodia</li>
              <li>Swift &amp; SwiftUI</li>
              <li>Open source · MIT</li>
            </ul>
            <div className="actions">
              <a className="btn" href="#contact">Get in touch</a>
              <a className="btn btn--ghost" href={GITHUB_PROFILE_URL} target="_blank" rel="noreferrer">
                GitHub profile ↗
              </a>
            </div>
          </div>
        </section>

        <section className="about-section" aria-labelledby="about-why">
          <p className="label">Why it exists</p>
          <h2 className="title" id="about-why">A notch that earns its place.</h2>
          <div className="about-prose">
            <p>
              The notch takes a slice out of the top of every recent MacBook display and
              gives nothing back. Bondex Notch turns that space into a quiet, live surface:
              what is playing, what a coding agent is doing and whether it needs you, what
              just downloaded — there at a glance, and out of the way when it is not.
            </p>
            <p>
              It is a one-person project, so every release is shaped by the people who use
              it. Bug reports, ideas and questions go straight to the developer.
            </p>
          </div>
        </section>

        <section className="about-section" aria-labelledby="about-how">
          <p className="label">How it is built</p>
          <h2 className="title" id="about-how">Four rules every feature follows.</h2>
          <div className="about-principles">
            {principles.map(({ title, body }) => (
              <article className="about-principle" key={title}>
                <h3>{title}</h3>
                <p>{body}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="about-section" aria-labelledby="about-releases">
          <p className="label">Releases</p>
          <h2 className="title" id="about-releases">Shipped so far.</h2>
          <ol className="about-timeline">
            {releases.map(({ version, date, summary }) => (
              <li key={version}>
                <a href={`${GITHUB_REPO_URL}/releases/tag/v${version}`} target="_blank" rel="noreferrer">
                  <b>Bondex Notch {version}</b>
                  <time>{date}</time>
                </a>
                <p>{summary}</p>
              </li>
            ))}
          </ol>
          <p className="about-more">
            <Link href="/download/">Download the latest release</Link> ·{' '}
            <a href={GITHUB_REPO_URL} target="_blank" rel="noreferrer">Read the source</a>
          </p>
        </section>

        <section className="about-section" id="contact" aria-labelledby="about-contact">
          <p className="label">Get in touch</p>
          <h2 className="title" id="about-contact">Messages go straight to the developer.</h2>
          <div className="footer__contact-grid about-contacts">
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
        </section>
      </div>
    </main>
  );
}
