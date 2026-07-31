# Bondex Notch — marketing site

Static, dependency-free: four files, no build step, no framework.

```
index.html   structure and copy
styles.css   the whole design system
field.js     the Ribbon Field wallpaper (canvas)
app.js       the notch bar, the interactive notch demo, tab switching
```

## Run it

```bash
python3 -m http.server 4173 --directory bondex-notch-web
```

Then open <http://localhost:4173>. Opening `index.html` directly works too.
Deploy by copying the four files to any static host.

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

`field.js` renders the 21st.dev "my gradient" Ribbon Field to a canvas.

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
- Hero and download copy sit on the bare field, so each of those sections lays
  a soft radial pool of shade under its own text.

The field is static (`animated: false` in the source parameters), so it renders
once on load and again on a debounced resize, into a buffer capped at 1100px on
its longest edge and upscaled. Roughly 0.7 MP of work, once.

## The demo

The hero contains a working replica of the panel, driven by the same state
machine as the app: `collapsed → peek → expanded`, hover to open, click to pin,
`Escape` to close. It is keyboard reachable and announces its state via
`aria-expanded`.

The concave fillets either side of the notch are drawn with `box-shadow` on two
pseudo-elements rather than SVG, so the shape animates with the panel width. The
same trick draws the notch bar at the top of the page and the three to-scale
minis in the "Three states" section.

Before the visitor touches it, an ambient loop alternates collapsed and peek so
the hero reads as live rather than as a screenshot. It stops permanently on
first interaction, and never starts under `prefers-reduced-motion`.

## Conventions

- **Type.** Archivo for display (variable on the width axis — the hero headline
  opens from `wdth` 74 to 112 on load, once, the way the panel widens when it
  wakes), DM Sans for body, JetBrains Mono for labels and the panel's readouts,
  where tabular figures are the point. This replaces the previous
  system-font-only rule: the site now has its own identity rather than
  impersonating the platform. Cost is one Google Fonts request.
- **Palette is dark-on-saturated in every mode.** The product is a black panel
  on a desktop, and a light rendering would misrepresent it.
  `prefers-contrast: more` firms up text, slabs and hairlines and drops the
  grain to `.3`.
- Below 900px the slabs drop `backdrop-filter` and go near-opaque — blurring a
  full-screen canvas is expensive on mobile GPUs and buys nothing there.
- The demo panel is fixed-width by nature. Below 900px it is scaled rather than
  reflowed, because a reflowed panel would no longer be the product.

## Before going live

- `#download` and the GitHub button are `href="#"` placeholders.
- Pricing shows $14.99 one-time and $4/month for the AI add-on, mid-range of the
  proposal's $9.99–$19.99 and $3–$5. Confirm before publishing.
- The "Genuinely light" card deliberately does not quote a memory figure. Add
  one only once it has been measured on a release build.
- Fonts load from Google Fonts. Self-host the four files if you'd rather not
  depend on a third party at runtime.
