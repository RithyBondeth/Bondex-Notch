# Bondex Notch — marketing site

Next.js 16 (App Router, React 19, TypeScript), built as a fully static export.

```
app/layout.tsx      metadata, fonts, the wallpaper and the notch bar
app/page.tsx        section order
app/globals.css     the whole design system
components/         one component per section, plus the three client ones
content/site.ts     features, panel states and pricing as typed data
lib/ribbonField.ts  the gradient maths, framework-free
```

## Run it

```bash
cd bondex-notch-web && npm install && npm run dev
```

Then open <http://localhost:4173>.

```bash
npm run build
```

Writes plain files to `out/`. `npm start` serves that production export locally.

## Quality gates

Run the same checks as CI before opening a pull request:

```bash
npm run audit
npm run lint
npm run typecheck
npm run build
npx playwright install chromium # first local run only
npm test
```

The Playwright suite checks the landing page, every legal/support route,
canonical metadata, narrow-screen legal layout, and the checkout preview. The
checkout test also verifies that submitting locally validated fields does not
make a payment request.

`.github/workflows/web-ci.yml` runs these checks for web pull requests and every
push to `main`. A high-severity dependency advisory fails CI.

## Deployment and rollback

Vercel is the only production hosting path for this site. The Vercel project
must use `bondex-notch-web` as its **Root Directory** and the repository default
branch (`main`) as its production branch. Pull requests receive Preview
deployments; merges to `main` produce Production deployments. `vercel.json`
keeps framework detection explicit, and the Next.js static export requires no
runtime service or application secrets.

`vercel.json` also applies the production security boundary to every route:
Content Security Policy, MIME sniffing protection, a strict cross-origin
referrer policy, a restrictive browser Permissions Policy, and framing
protection. The static export uses Next.js inline bootstrap scripts and inline
component styles, so CSP permits inline scripts and styles but does not permit
`eval`, third-party script origins, arbitrary network connections, plugins, or
framing.

If a production deployment is unhealthy:

1. Verify the problem on the production domain.
2. In Vercel, open **Deployments**, select **Instant Rollback**, and restore the
   previous healthy production deployment. From a linked CLI, `vercel rollback`
   performs the same immediate rollback.
3. Verify the production domain again, then fix the source on a pull request so
   `main` matches the restored behavior.

Vercel documents both the [monorepo Root Directory
setting](https://vercel.com/docs/monorepos) and the [production rollback
workflow](https://vercel.com/docs/deployments/rollback-production-deployment).

## The idea

The product is a black panel that lives on top of your wallpaper, so the page
*is* the wallpaper. Three things follow from that:

- The **Ribbon Field** gradient runs full-bleed and fixed behind everything.
- The **navigation is a notch** — a black pill hanging off the top edge of the
  viewport with the same concave fillets the app draws, which collapses from
  56px to 46px as you scroll, the way the panel collapses when you move the
  pointer away.
- Content sits on **black glass slabs** floating on the field, and the demo's
  screen is transparent, so the wallpaper you see through it is the page's own.

## The Ribbon Field

`lib/ribbonField.ts` paints the 21st.dev "my gradient" Ribbon Field to a canvas.
`components/RibbonField.tsx` is a thin client wrapper around it.

The stop list in that file is the exact stripe layout 21st.dev computes from the
source parameters (angle 135, scale 68, count 6, spread −20, softness 26,
envelope `ramp`) — the short runs between flat colour runs are the feathered
stripe edges, so sampling it linearly reproduces the published CSS exactly.

What canvas adds, and a CSS gradient cannot, is `wave`: each band is bent by a
cross-axis sine offset of `(wave / 100) * 0.35 * sin(cross * 2.4 * 2π + clock)`.

Grain and vignette are layered on in CSS (`.field::before` / `::after`), in the
reference's stacking order: noise in `overlay` over the vignette over the field.
Two deliberate departures from the published values, both for legibility:

- The grain layer is held at `opacity: .55` rather than full strength. The
  bitmap itself is the reference texture, unmodified.
- The hero, the download call to action and the states heading are the only copy
  set directly on the bare field, so each pools a little shade under its own
  text. White type on its own is not enough where the pale Mauve ribbon crosses.

The field is static (`animated: false` in the source parameters), so it paints
once on mount and again on a debounced resize, into a buffer capped at 1100px on
its longest edge and upscaled. Roughly 0.7 MP of work, once.

`.field` is promoted with `transform: translateZ(0)`. Without it a full-viewport
fixed canvas sitting under blended and blurred content gets dropped by the
compositor part-way down the page, and whole sections render as flat colour.

## The demo

The hero contains a working replica of the panel, driven by the same state
machine as the app: `collapsed → peek → expanded`, hover to open, click to pin,
`Escape` to close. It is keyboard reachable and announces its state via
`aria-expanded`.

`idleState` and `pinned` are refs rather than state — the ambient loop and the
close timer both read them from callbacks that outlive a render, and neither
should trigger one on its own.

The concave fillets either side of the notch are drawn with `box-shadow` on two
pseudo-elements rather than SVG, so the shape animates with the panel width. The
same trick draws the notch bar at the top of the page and the three to-scale
minis in the "Three states" section.

Before the visitor touches it, an ambient loop alternates collapsed and peek so
the hero reads as live rather than as a screenshot. It stops permanently on
first interaction, and never starts under `prefers-reduced-motion`.

## Conventions

- **One global stylesheet, not CSS Modules.** The design is a small token system
  with primitives (`.btn`, `.label`, `.title`, `.slab`) that cut across every
  section. Scoping them per component would fragment the system without making
  anything safer.
- **Server components by default.** Only the wallpaper, the notch bar and the
  demo are client components; every other section ships no JavaScript.
- **Content lives in `content/site.ts`.** The panel-state diagram reads its
  widths from there rather than from CSS, because those are facts about the
  product, not styling.
- **Type.** Archivo for display (variable on the width axis — the hero headline
  opens from `wdth` 74 to 112 on load, once, the way the panel widens when it
  wakes), DM Sans for body, JetBrains Mono for labels and the panel's readouts,
  where tabular figures are the point. All three are self-hosted at build time
  by `next/font`, so the exported HTML makes no third-party requests. The
  headline animation is pure CSS, so it survives with JavaScript disabled.
- **Palette is dark-on-saturated in every mode.** The product is a black panel
  on a desktop, and a light rendering would misrepresent it.
  `prefers-contrast: more` firms up text, slabs and hairlines and drops the
  grain to `.3`.
- Below 900px the slabs drop `backdrop-filter` and go near-opaque — blurring a
  full-screen canvas is expensive on mobile GPUs and buys nothing there.
- The demo panel is fixed-width by nature. Below 900px it is scaled rather than
  reflowed, because a reflowed panel would no longer be the product.

## Before going live

- The download section links to the repository's quick-start instructions until
  the first signed release is published.
- Pricing shows one complete $14.99 lifetime licence after a full 24-hour trial.
  Confirm the final price before publishing.
- The "Genuinely light" card deliberately does not quote a memory figure. Add
  one only once it has been measured on a release build.
