# Bondex Notch

A native macOS productivity utility that turns the display notch into a live,
Dynamic Island-style surface — and the site that sells it.

| Directory | What it is |
|---|---|
| [`bondex-notch-app`](bondex-notch-app/) | The macOS app. Swift 6, SwiftUI, AppKit, no dependencies. |
| [`bondex-notch-web`](bondex-notch-web/) | The marketing and Stripe Checkout site. Next.js 16, React 19, TypeScript, deployed on Vercel. |
| [`docs`](docs/) | Original project proposal. |

## Quick start

```bash
cd bondex-notch-app && ./scripts/build-app.sh release --universal && open "build/Bondex Notch.app"
```

```bash
cd bondex-notch-web && npm install && npm run dev
```

Each directory has its own README with architecture notes and caveats. Two
points worth knowing up front, both covered in detail in
[the app README](bondex-notch-app/README.md):

- Media is read from the playing app itself, because macOS exposes no public
  system-wide Now Playing API: Music and Spotify over their scripting
  dictionaries, browser tabs by evaluating a small script in the tab that owns
  the audio. Web players need "Allow JavaScript from Apple Events" enabled once
  per browser; the panel says so when it is still off.
- The "Activity" widget is a feed of events Bondex observes itself. No Mac app
  can read other applications' notifications.

Requires macOS 14 or later and Xcode 16+ to build. The universal release runs
natively on both Apple Silicon and Intel Macs.

## Environment configuration

- `bondex-notch-web/.env.example` lists every public and server-only value used
  by the website and Stripe Checkout. Copy it to `.env.local` for local work;
  configure production values in Vercel and never commit real secrets.
- `bondex-notch-app/.env.example` lists the build-time checkout URL consumed by
  `scripts/build-app.sh`. Export it in the shell before assembling the app.

The Stripe-hosted flow does not need a publishable browser key because card
collection happens on Stripe rather than inside Bondex.
