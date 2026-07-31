/* Ribbon Field — the page wallpaper.

   A canvas stripe field along a 135° axis. The stop list below is the exact
   stripe layout 21st.dev computes from the source parameters (scale 68,
   count 6, spread -20, softness 26, envelope "ramp") — the short runs between
   flat colour runs are the feathered stripe edges. Sampling it linearly
   therefore reproduces the CSS approximation exactly.

   What canvas adds, and CSS cannot: `wave` bends each band by a cross-axis
   sine offset of (wave / 100) * 0.35 * sin(cross * 2.4 * 2π + clock).

   Grain and vignette are layered on in CSS (see .field::before / ::after),
   which matches the reference stacking order: noise (overlay) over vignette
   over the field.

   Deliberately framework-free — the React component is a thin wrapper. */

export const RIBBON_FIELD = {
  angle: 135,
  wave: 12,
  seed: 1,
  /* Longest edge of the render buffer. The field is smooth, so it upscales to
     any viewport without a visible seam and costs one pass regardless of how
     large the window is. */
  maxSide: 1100,
} as const;

/** Base colour, used until the canvas has painted. */
export const FIELD_BACKDROP = '#1D62D7';

const STOPS: ReadonlyArray<{ p: number; c: string }> = [
  { p: 0.0091, c: '#1D62D7' }, // Lagoon blue
  { p: 0.4259, c: '#1D62D7' },
  { p: 0.4389, c: '#C3CFEA' }, // Mauve
  { p: 0.4811, c: '#C3CFEA' },
  { p: 0.4889, c: '#3CC1F6' }, // Glazed azure
  { p: 0.5611, c: '#3CC1F6' },
  { p: 0.5819, c: '#1839A7' }, // Lapis
  { p: 0.7981, c: '#1839A7' },
  { p: 0.815, c: '#1E788A' }, // Cobalt
  { p: 1.0, c: '#1E788A' },
];

const RAMP_N = 2048;

const clamp01 = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v);

function buildRamp(): Uint8ClampedArray {
  const rgb = STOPS.map(({ p, c }) => ({
    p,
    r: parseInt(c.slice(1, 3), 16),
    g: parseInt(c.slice(3, 5), 16),
    b: parseInt(c.slice(5, 7), 16),
  }));
  const out = new Uint8ClampedArray(RAMP_N * 3);
  let i = 0;

  for (let n = 0; n < RAMP_N; n++) {
    const t = n / (RAMP_N - 1);
    while (i < rgb.length - 2 && t > rgb[i + 1].p) i++;
    const a = rgb[i];
    const b = rgb[i + 1];
    const span = b.p - a.p;
    const f = span <= 0 ? 0 : clamp01((t - a.p) / span);
    out[n * 3] = a.r + (b.r - a.r) * f;
    out[n * 3 + 1] = a.g + (b.g - a.g) * f;
    out[n * 3 + 2] = a.b + (b.b - a.b) * f;
  }
  return out;
}

let ramp: Uint8ClampedArray | null = null;

/**
 * Paints the field into `canvas`, sized to the given viewport. Returns false if
 * the 2D context is unavailable, so the caller can fall back to the flat
 * backdrop colour.
 */
export function renderRibbonField(
  canvas: HTMLCanvasElement,
  viewportWidth: number,
  viewportHeight: number,
): boolean {
  const ctx = canvas.getContext('2d', { alpha: false });
  if (!ctx) return false;

  ramp ??= buildRamp();

  const vw = Math.max(1, viewportWidth);
  const vh = Math.max(1, viewportHeight);
  const ratio = Math.min(1, RIBBON_FIELD.maxSide / Math.max(vw, vh));
  const w = Math.max(2, Math.round(vw * ratio));
  const h = Math.max(2, Math.round(vh * ratio));

  canvas.width = w;
  canvas.height = h;

  const rad = (RIBBON_FIELD.angle * Math.PI) / 180;
  // CSS gradient convention: 0deg points up, angles run clockwise, y grows
  // downward on screen.
  const dx = Math.sin(rad);
  const dy = -Math.cos(rad);
  // Perpendicular, for the wave's cross-axis argument.
  const px = -dy;
  const py = dx;

  const axisLen = Math.abs(w * dx) + Math.abs(h * dy);
  const crossLen = Math.abs(w * px) + Math.abs(h * py);
  const cx = w / 2;
  const cy = h / 2;

  const amp = (RIBBON_FIELD.wave / 100) * 0.35;
  const clock = RIBBON_FIELD.seed * 1.7;
  const TWO_PI = Math.PI * 2;

  const img = ctx.createImageData(w, h);
  const data = img.data;
  let o = 0;

  for (let y = 0; y < h; y++) {
    const oy = y - cy;
    const axisY = oy * dy;
    const crossY = oy * py;

    for (let x = 0; x < w; x++) {
      const ox = x - cx;
      const t = 0.5 + (ox * dx + axisY) / axisLen;
      const cross = 0.5 + (ox * px + crossY) / crossLen;

      const bent = t + amp * Math.sin(cross * 2.4 * TWO_PI + clock);
      const s = ((clamp01(bent) * (RAMP_N - 1)) | 0) * 3;

      data[o] = ramp[s];
      data[o + 1] = ramp[s + 1];
      data[o + 2] = ramp[s + 2];
      data[o + 3] = 255;
      o += 4;
    }
  }

  ctx.putImageData(img, 0, 0);
  return true;
}
