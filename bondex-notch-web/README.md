# Bondex Notch — marketing site

Static, dependency-free: three files, no build step, no framework.

```
index.html   structure and copy
styles.css   the whole design system
app.js       sticky nav, the interactive notch demo, tab switching
```

## Run it

```bash
python3 -m http.server 4173 --directory bondex-notch-web
```

Then open <http://localhost:4173>. Opening `index.html` directly works too.
Deploy by copying the three files to any static host.

## The demo

The hero contains a working replica of the panel, driven by the same state
machine as the app: `collapsed → peek → expanded`, hover to open, click to pin,
`Escape` to close. It is keyboard reachable and announces its state via
`aria-expanded`.

The concave fillets either side of the notch are drawn with `box-shadow` on two
pseudo-elements rather than SVG, so the shape animates with the panel width.

Before the visitor touches it, an ambient loop alternates collapsed and peek so
the hero reads as live rather than as a screenshot. It stops permanently on
first interaction, and never starts under `prefers-reduced-motion`.

## Conventions

- The palette is intentionally dark-only: the product is a black panel on a
  desktop, and a light rendering would misrepresent it. `prefers-contrast: more`
  is honoured.
- System font stack only — the site should look like the platform the app runs
  on, and it avoids a webfont round trip.
- The demo panel is fixed-width by nature. Below 860px it is scaled rather than
  reflowed, because a reflowed panel would no longer be the product.

## Before going live

- `#download` and the GitHub button are `href="#"` placeholders.
- Pricing shows $14.99 one-time and $4/month for the AI add-on, mid-range of the
  proposal's $9.99–$19.99 and $3–$5. Confirm before publishing.
- The "Genuinely light" card deliberately does not quote a memory figure. Add
  one only once it has been measured on a release build.
