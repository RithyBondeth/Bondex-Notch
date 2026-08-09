import type { ReactNode } from 'react';

/* The answers carry markup, so they live here rather than in the content
   module. The first is open by default — it is the question the product is
   most often wrong about elsewhere. */

const answers: Array<{ q: string; a: ReactNode; plainText: string; open?: boolean }> = [
  {
    q: 'Which music apps are supported?',
    open: true,
    plainText:
      'Apple Music, Spotify, Safari, and supported Chromium browsers. Bondex uses each app’s supported scripting interface. Browser tabs can show players such as YouTube, YouTube Music, SoundCloud and Twitch after JavaScript from Apple Events is enabled once.',
    a: (
      <>
        Apple Music, Spotify, Safari, and supported Chromium browsers. macOS has no public system-wide &quot;now
        playing&quot; API — <code>MPNowPlayingInfoCenter</code> only reports the
        calling process, and the private framework that used to work was locked
        down in macOS 15.4. Bondex uses each app&apos;s scripting interface
        instead, which is the supported route. Browser tabs can show players such
        as YouTube, YouTube Music, SoundCloud and Twitch after JavaScript from
        Apple Events is enabled once. You&apos;ll be asked for Automation permission
        the first time.
      </>
    ),
  },
  {
    q: 'How does agent activity work?',
    plainText:
      'A small hook tells Bondex when an agent starts a tool, what it is doing, and when the turn ends. Codex and Claude Code have direct setup flows; Gemini, Ollama, and other CLI agents can use the same local busy and idle signal.',
    a: (
      <>
        A small hook tells Bondex when an agent starts a tool, what it is doing,
        and when the turn ends. Codex and Claude Code have direct setup flows;
        Gemini, Ollama, and any other CLI agent can use the same open busy/idle
        signal. Everything stays on your Mac and is watched without background
        polling.
      </>
    ),
  },
  {
    q: 'What are custom live activities?',
    plainText:
      'Progress updates sent from a script, Shortcut, build tool or terminal with no SDK required. A live activity can include a title, status and progress value, stays visible in the peek, and becomes an activity-feed event when it finishes.',
    a: (
      <>
        Progress updates that you send from a script, Shortcut, build tool or
        terminal — no SDK needed. A live activity can have a title, status and
        progress value; it stays visible in the peek and becomes an activity-feed
        event when it finishes.
      </>
    ),
  },
  {
    q: 'How private are Quick Capture and clipboard history?',
    plainText:
      'Captures stay on your Mac. Clipboard history is session-only, is never written to disk, ignores concealed or transient content, and can be paused. Optional capture enhancement is user-triggered and runs on-device on supported Macs.',
    a: (
      <>
        Captures stay on your Mac. Clipboard history is session-only, is never
        written to disk, and ignores content marked concealed or transient by the
        source app. You can pause it whenever you like. Capture enhancement is a
        separate, user-triggered action that uses on-device Apple Intelligence on
        supported macOS 26 Macs; ordinary capture never requires it.
      </>
    ),
  },
  {
    q: 'Can I automate Bondex?',
    plainText:
      'Yes. Bondex exposes App Intents to Apple Shortcuts for switching profiles, changing automatic profile mode, creating a quick capture, starting a focus timer and showing a widget. Global keyboard shortcuts can also open the panel, Quick Capture and command palette.',
    a: (
      <>
        Yes. Bondex exposes App Intents to Apple Shortcuts for switching profiles,
        changing automatic profile mode, creating a quick capture, starting a focus
        timer and showing a widget. You can also assign global keyboard shortcuts to
        the panel, Quick Capture and command palette.
      </>
    ),
  },
  {
    q: "Does it show my other apps' notifications?",
    plainText:
      'No. macOS does not provide an API for reading other apps’ Notification Center items. Bondex instead shows an activity feed for events it observes directly, including track changes, completed downloads, power events and shelf drops.',
    a: (
      <>
        No, and no Mac app can. Notification Center&apos;s database is protected
        by System Integrity Protection and there&apos;s no API to read it. Rather
        than pretend otherwise, Bondex shows an <em>activity feed</em>: what it
        observes directly — track changes, completed downloads, power events,
        shelf drops.
      </>
    ),
  },
  {
    q: 'How light is it on CPU and memory?',
    plainText:
      'Bondex is a native Swift app with no Electron runtime, web view or background helper process. System metrics are sampled every two seconds on a background utility task, and disabled widgets stop their services entirely.',
    a: (
      <>
        It&apos;s a native Swift app with no Electron runtime, web view, or
        background helper process. System metrics are sampled every two seconds
        on a background utility task, and widgets you disable stop their service
        entirely. Exact usage varies by Mac and enabled widgets, so Activity
        Monitor is the honest place to verify it on your setup.
      </>
    ),
  },
  {
    q: 'What permissions does it ask for?',
    plainText:
      'Up to four optional permissions requested only for the relevant feature: Automation for Music and Spotify, Files and Folders for Downloads, Notifications for Bondex alerts, and Calendar for upcoming meetings. Privacy indicators do not require camera or microphone permission.',
    a: (
      <>
        Up to four, all optional and requested only for the relevant feature:
        <b> Automation</b> for Music and Spotify, <b>Files and Folders</b> to
        watch Downloads, <b>Notifications</b> for Bondex alerts, and
        <b> Calendar</b> for upcoming meetings. Privacy indicators do not need
        camera or microphone permission and never record either source. Nothing
        leaves your Mac.
      </>
    ),
  },
  {
    q: 'Will it work on my display?',
    plainText:
      'Bondex supports macOS 14 Sonoma or later on Apple silicon and Intel. On displays without a hardware notch, it draws a matching pill in the same position.',
    a: (
      <>
        macOS 14 Sonoma or later, Apple silicon or Intel. Notch or no notch — on
        displays without one, Bondex draws a matching pill in the same position.
      </>
    ),
  },
];

export const faqJsonLd = {
  '@context': 'https://schema.org',
  '@type': 'FAQPage',
  mainEntity: answers.map(({ q, plainText }) => ({
    '@type': 'Question',
    name: q,
    acceptedAnswer: {
      '@type': 'Answer',
      text: plainText,
    },
  })),
};

export default function Faq() {
  return (
    <section id="faq" className="section">
      <div className="wrap wrap--narrow">
        <div className="slab">
          <header className="slab__head">
            <p className="label">The honest answers</p>
            <h2 className="title">What it can and can&apos;t do</h2>
          </header>

          {answers.map(({ q, a, open }) => (
            <details className="qa" key={q} open={open}>
              <summary>{q}</summary>
              <p>{a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
