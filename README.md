<div align="center">

# Bondex Notch

**A free, open-source macOS utility that turns the display notch into a live, Dynamic Island-style surface, plus the website that distributes it.**

![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-0D96F6?style=for-the-badge&logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?style=for-the-badge&logo=typescript&logoColor=white)
![Next.js](https://img.shields.io/badge/Next.js-000000?style=for-the-badge&logo=nextdotjs&logoColor=white)
![React](https://img.shields.io/badge/React-61DAFB?style=for-the-badge&logo=react&logoColor=white)

</div>

---

## Overview

Bondex Notch turns the MacBook display notch into a live view of what your Mac is doing: music, downloads, system status, meetings, AI coding-agent activity, and a drag-and-drop shelf. It runs as a menu-bar agent with no Dock icon, never steals focus, and lets clicks pass through to the apps underneath.

This repository contains both the native app and its website:

| Directory | Contents |
| --- | --- |
| [`bondex-notch-app`](bondex-notch-app/) | The macOS app: Swift 6, SwiftUI, AppKit, with Sparkle for updates |
| [`bondex-notch-web`](bondex-notch-web/) | The website and download page: Next.js 16, React 19, TypeScript, deployed on Vercel |
| [`docs`](docs/) | The original project proposal |

## Features

- **Now playing:** controls for Music, Spotify, and browser audio tabs.
- **Live activities:** downloads and file activity, focus timers, upcoming calendar meetings, and device battery levels.
- **System metrics** and a custom system HUD.
- **Drag-and-drop shelf** for holding files temporarily.
- **Clipboard history** and quick capture.
- **Command palette** with global hotkeys and custom AppleScript actions.
- **AI agent activity:** live status and usage tracking for AI coding agents.
- **Privacy indicators** for camera and microphone activity.
- **Smart profiles,** App Intents and Shortcuts support, and an onboarding flow.
- **Signed automatic updates** through Sparkle (EdDSA-verified, opt-in).
- **Universal build** that runs natively on Apple Silicon and Intel Macs.

## Tech Stack

| Area | Technology |
| --- | --- |
| App | Swift 6, SwiftUI, AppKit, Swift Package Manager |
| Updates | Sparkle (signed appcast and EdDSA-verified downloads) |
| Website | Next.js 16, React 19, TypeScript |
| Testing | XCTest (`swift test`), Playwright |
| CI and hosting | GitHub Actions, GitHub Releases, Vercel |

## Getting Started

### Prerequisites

- macOS 14 or later
- Xcode 16 or later
- Node.js and npm (for the website)

### Build the App

```bash
git clone https://github.com/RithyBondeth/Bondex-Notch.git
cd Bondex-Notch/bondex-notch-app
./scripts/build-app.sh release --universal
open "build/Bondex Notch.app"
```

| Command | Description |
| --- | --- |
| `./scripts/build-app.sh debug` | Faster build for the current Mac only |
| `./scripts/build-dmg.sh` | Package a universal `.dmg` installer |
| `swift test` | Run the test suite |
| `./scripts/release.sh <version> --notes notes.md` | Sign, tag, and publish a release |

### Run the Website

```bash
cd bondex-notch-web
cp .env.example .env.local
npm install
npm run dev
```

Open [http://localhost:4173](http://localhost:4173).

## Good to Know

- **Media is read from the playing app itself,** because macOS has no public system-wide Now Playing API. Web players need "Allow JavaScript from Apple Events" turned on once per browser, and the panel tells you when it is still off.
- **The Activity widget** is a feed of events Bondex observes itself. No Mac app can read other applications' notifications.
- **First install** of a build without an Apple Developer ID needs **Open Anyway** in Privacy & Security.

See the [app README](bondex-notch-app/README.md) for architecture details, release signing, and update internals.

## Project Structure

```text
Bondex-Notch/
├── bondex-notch-app/
│   ├── Sources/BondexNotch/
│   │   ├── App/        # Entry point, delegate, composition root, menu bar
│   │   ├── Window/     # NSPanel, geometry, pointer tracking, panel state machine
│   │   ├── Model/      # Preferences, events, state
│   │   ├── Services/   # Now playing, metrics, files, shelf, clipboard, agents, calendar
│   │   ├── Views/      # Notch silhouette, widgets, settings, command palette
│   │   └── Support/    # Theme, motion, logging, preview renderer
│   ├── Resources/      # Info.plist, entitlements, Sparkle keys, app icon
│   └── scripts/        # Build, DMG, and release scripts
├── bondex-notch-web/   # Next.js website and download page
└── docs/               # Project proposal
```

## Author

**Rithy Bondeth** — Full Stack Developer & AI Engineer

[![Portfolio](https://img.shields.io/badge/Portfolio-0A0A0A?style=for-the-badge&logo=vercel&logoColor=white)](https://bondeth.dev)
[![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/RithyBondeth)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/rithy-bondeth-484073282/)

## License

Distributed under the MIT License. See [`LICENSE`](LICENSE) for details.
