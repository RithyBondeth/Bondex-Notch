'use client';

import { useEffect, useRef } from 'react';
import { BUDDY_MOOD_TITLES, type BuddyMood, buddyMood } from './model';

/* BuddyMascot, ported from the Swift Canvas drawing so the site's buddy is the
   app's: the same 100 × 100 drawing space, the same poses for each degree of
   energy, the same breathing, blinking, gaze and hop. Animated only while on
   screen, and still under prefers-reduced-motion. */

type Props = {
  energy: number;
  thirsty?: boolean;
  /** Changes each time water is logged; plays a splash and a hop. */
  waterTick?: number;
  /** Follows the pointer and hops when clicked. */
  interactive?: boolean;
  size: number;
  /** Frames per second while idling. */
  fps?: number;
};

const VIEW = { x: 7, y: 12, size: 86 };
const SPLASH_LENGTH = 0.9;
const REACTION_LENGTH = 1.1;

export default function BuddyMascot({ energy, thirsty = false, waterTick = 0, interactive = false, size, fps = 30 }: Props) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const live = useRef({ energy, thirsty, gaze: { x: 0, y: 0 }, splashAt: -1, reactionAt: -1 });
  const firstWater = useRef(waterTick);
  const lastEnergy = useRef(energy);

  useEffect(() => {
    live.current.energy = energy;
    live.current.thirsty = thirsty;
    // A jump in energy is a break just taken: worth a little celebration.
    if (energy - lastEnergy.current > 0.15) live.current.reactionAt = performance.now() / 1000;
    lastEnergy.current = energy;
  }, [energy, thirsty]);

  useEffect(() => {
    if (waterTick === firstWater.current) return;
    const now = performance.now() / 1000;
    live.current.splashAt = now;
    live.current.reactionAt = now + SPLASH_LENGTH * 0.55;
  }, [waterTick]);

  useEffect(() => {
    const element = canvas.current;
    if (!element) return;
    const context = element.getContext('2d');
    if (!context) return;
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    const ratio = Math.min(window.devicePixelRatio || 1, 3);
    element.width = Math.round(size * ratio);
    element.height = Math.round(size * ratio);

    let frame = 0;
    let last = 0;
    let visible = true;
    const render = (stamp: number) => {
      frame = requestAnimationFrame(render);
      if (!visible || stamp - last < 1000 / fps) return;
      last = stamp;
      const now = stamp / 1000;
      const state = live.current;
      const progress = (start: number, length: number) => {
        const value = (now - start) / length;
        return start >= 0 && value >= 0 && value < 1 ? value : null;
      };
      context.setTransform(1, 0, 0, 1, 0, 0);
      context.clearRect(0, 0, element.width, element.height);
      const scale = (size * ratio) / VIEW.size;
      context.setTransform(scale, 0, 0, scale, -VIEW.x * scale, -VIEW.y * scale);
      draw(context, {
        energy: Math.min(Math.max(state.energy, 0), 1),
        thirsty: state.thirsty,
        time: reduced.matches ? 0 : now,
        splash: reduced.matches ? null : progress(state.splashAt, SPLASH_LENGTH),
        reaction: reduced.matches ? null : progress(state.reactionAt, REACTION_LENGTH),
        gaze: state.gaze,
      });
      if (reduced.matches) cancelAnimationFrame(frame);
    };
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      if (visible && reduced.matches) render(performance.now() + 1000);
    });
    observer.observe(element);
    frame = requestAnimationFrame(render);
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
    };
  }, [size, fps]);

  const mood = buddyMood(energy);
  return (
    <canvas
      ref={canvas}
      className={`ap-buddy-mascot${interactive ? ' is-interactive' : ''}`}
      style={{ width: size, height: size }}
      role="img"
      aria-label={`Wellness buddy: ${BUDDY_MOOD_TITLES[mood]}, ${Math.round(energy * 100)} percent energy`}
      title={interactive ? 'Say hi' : undefined}
      onPointerMove={interactive ? (event) => {
        const box = event.currentTarget.getBoundingClientRect();
        live.current.gaze = {
          x: Math.min(Math.max(((event.clientX - box.left) / box.width) * 2 - 1, -1), 1),
          y: Math.min(Math.max(((event.clientY - box.top) / box.height) * 2 - 1, -1), 1),
        };
      } : undefined}
      onPointerLeave={interactive ? () => { live.current.gaze = { x: 0, y: 0 }; } : undefined}
      onClick={interactive ? (event) => {
        event.stopPropagation();
        live.current.reactionAt = performance.now() / 1000;
      } : undefined}
    />
  );
}

/* ── The drawing · BuddyDrawing ──────────────────────────── */

type Scene = {
  energy: number;
  thirsty: boolean;
  time: number;
  splash: number | null;
  reaction: number | null;
  gaze: { x: number; y: number };
};

type Ctx = CanvasRenderingContext2D;
type Point = { x: number; y: number };
type RGB = [number, number, number];

const INK = 'rgb(43, 20, 15)';
const TERRACOTTA_LIGHT = 'rgb(242, 158, 117)';
const TERRACOTTA = 'rgb(219, 122, 87)';
const TERRACOTTA_DEEP = 'rgb(153, 74, 51)';
const CREAM = 'rgba(255, 235, 204, 0.85)';

const rgba = ([r, g, b]: RGB, alpha = 1) => `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}, ${alpha})`;
const clamp = (value: number) => Math.min(Math.max(value, 0), 1);
const mix = (a: RGB, b: RGB, t: number): RGB => {
  const k = clamp(t);
  return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k];
};

function ellipse(ctx: Ctx, x: number, y: number, width: number, height: number) {
  ctx.beginPath();
  ctx.ellipse(x + width / 2, y + height / 2, Math.abs(width / 2), Math.abs(height / 2), 0, 0, Math.PI * 2);
}

function linear(ctx: Ctx, from: Point, to: Point, stops: Array<[number, string]>) {
  const gradient = ctx.createLinearGradient(from.x, from.y, to.x, to.y);
  stops.forEach(([at, color]) => gradient.addColorStop(at, color));
  return gradient;
}

function radial(ctx: Ctx, center: Point, radius: number, stops: Array<[number, string]>) {
  const gradient = ctx.createRadialGradient(center.x, center.y, 0, center.x, center.y, radius);
  stops.forEach(([at, color]) => gradient.addColorStop(at, color));
  return gradient;
}

function dropPath(ctx: Ctx, center: Point, size: number) {
  const radius = size * 0.42;
  ctx.beginPath();
  ctx.moveTo(center.x, center.y - size * 0.62);
  ctx.quadraticCurveTo(center.x + radius * 0.35, center.y - size * 0.3, center.x + radius, center.y + size * 0.05);
  ctx.arc(center.x, center.y + size * 0.05, radius, 0, Math.PI, false);
  ctx.quadraticCurveTo(center.x - radius * 0.35, center.y - size * 0.3, center.x, center.y - size * 0.62);
}

function heartPath(ctx: Ctx, center: Point, size: number) {
  const bottom = { x: center.x, y: center.y + size };
  ctx.beginPath();
  ctx.moveTo(bottom.x, bottom.y);
  ctx.bezierCurveTo(center.x - size * 1.6, center.y - size * 0.1, center.x - size * 0.6, center.y - size * 1.3, center.x, center.y - size * 0.45);
  ctx.bezierCurveTo(center.x + size * 0.6, center.y - size * 1.3, center.x + size * 1.6, center.y - size * 0.1, bottom.x, bottom.y);
}

function draw(ctx: Ctx, scene: Scene) {
  const { energy, time, reaction, gaze } = scene;
  const tiredness = 1 - energy;
  const mood: BuddyMood = buddyMood(energy);
  const delighted = reaction !== null;
  const hop = reaction === null ? 0 : Math.sin(Math.min(reaction / 0.45, 1) * Math.PI) * 6;

  const leafColor = (shade: number) => {
    const fresh: RGB = [0.32, 0.8, 0.44];
    const tired: RGB = [0.74, 0.71, 0.32];
    const spent: RGB = [0.62, 0.47, 0.26];
    const base = energy >= 0.5 ? mix(tired, fresh, (energy - 0.5) / 0.5) : mix(spent, tired, energy / 0.5);
    return rgba([clamp(base[0] + shade), clamp(base[1] + shade), clamp(base[2] + shade)]);
  };
  const moodTint: RGB = {
    thriving: [0.55, 0.95, 0.6] as RGB,
    content: [0.7, 0.9, 0.45] as RGB,
    droopy: [1, 0.76, 0.32] as RGB,
    wilting: [1, 0.45, 0.35] as RGB,
  }[mood];

  // Glow
  ellipse(ctx, 8, 20, 84, 80);
  ctx.fillStyle = radial(ctx, { x: 50, y: 62 }, 42, [[0, rgba(moodTint, delighted ? 0.34 : 0.22)], [1, rgba(moodTint, 0)]]);
  ctx.fill();

  // Sparkles
  if (mood === 'thriving' || delighted) {
    const spots: Array<[number, number, number, number]> = [[22, 36, 0, 3.2], [79, 28, 2.1, 2.6], [80, 56, 4, 2.2], [18, 60, 5.3, 1.8]];
    for (const [x, y, phase, size] of spots) {
      const twinkle = time === 0 ? 0.7 : Math.max(Math.sin(time * 1.8 + phase), 0);
      if (twinkle <= 0.05) continue;
      const s = size * twinkle;
      ctx.beginPath();
      ctx.moveTo(x, y - s);
      ctx.quadraticCurveTo(x, y, x + s, y);
      ctx.quadraticCurveTo(x, y, x, y + s);
      ctx.quadraticCurveTo(x, y, x - s, y);
      ctx.quadraticCurveTo(x, y, x, y - s);
      ctx.fillStyle = `rgba(255, 242, 191, ${0.85 * twinkle})`;
      ctx.fill();
    }
  }

  // Shadow
  const shrink = hop / 12;
  ellipse(ctx, 26 + shrink * 8, 91.5, 48 - shrink * 16, 7);
  ctx.fillStyle = radial(ctx, { x: 50, y: 95 }, 24, [[0, `rgba(0,0,0,${0.5 - shrink * 0.2})`], [1, 'rgba(0,0,0,0)']]);
  ctx.fill();

  // Everything that hops and breathes together.
  ctx.save();
  const breath = Math.sin(time * (1.4 + energy)) * 0.014 * (0.4 + energy);
  let stretch = breath;
  if (reaction !== null) stretch += Math.sin(reaction * Math.PI * 4) * 0.08 * (1 - reaction);
  ctx.translate(50, 95 - hop);
  ctx.scale(1 - stretch * 0.7, 1 + stretch);
  ctx.translate(-50, -95);

  // Stem
  const base = { x: 50, y: 59 };
  const height = 26 + 10 * energy;
  const sway = Math.sin(time * 1.5) * 0.05 * (0.3 + energy) + gaze.x * 0.1 * energy;
  const lean = tiredness * tiredness * 1.3 + sway;
  const tip = { x: base.x + Math.sin(lean) * height, y: base.y - Math.cos(lean) * height };
  const control = { x: base.x + sway * 8, y: base.y - height * 0.62 };
  const along = (t: number): Point => {
    const a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t;
    return { x: a * base.x + b * control.x + c * tip.x, y: a * base.y + b * control.y + c * tip.y };
  };
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.beginPath();
  ctx.moveTo(base.x, base.y);
  ctx.quadraticCurveTo(control.x, control.y, tip.x, tip.y);
  ctx.strokeStyle = linear(ctx, base, tip, [[0, leafColor(-0.2)], [1, leafColor(-0.04)]]);
  ctx.lineWidth = 3.4;
  ctx.stroke();
  ctx.beginPath();
  ctx.moveTo(base.x - 0.8, base.y);
  ctx.quadraticCurveTo(control.x - 0.8, control.y, tip.x - 0.8, tip.y);
  ctx.strokeStyle = 'rgba(255,255,255,0.2)';
  ctx.lineWidth = 0.9;
  ctx.stroke();

  // Leaves
  const flutter = Math.sin(time * 2.1) * 0.07 * energy;
  const droop = tiredness * 1.2;
  const leaf = (from: Point, angle: number, length: number) => {
    const dir = { x: Math.sin(angle), y: -Math.cos(angle) };
    const normal = { x: -dir.y, y: dir.x };
    const width = length * 0.4;
    const at = (t: number, side: number) => ({
      x: from.x + dir.x * length * t + normal.x * width * side,
      y: from.y + dir.y * length * t + normal.y * width * side,
    });
    const end = at(1, 0);
    const c1 = at(0.12, 1.15), c2 = at(0.72, 0.95), c3 = at(0.72, -0.75), c4 = at(0.14, -0.7);
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.bezierCurveTo(c1.x, c1.y, c2.x, c2.y, end.x, end.y);
    ctx.bezierCurveTo(c3.x, c3.y, c4.x, c4.y, from.x, from.y);
    ctx.fillStyle = linear(ctx, from, end, [[0, leafColor(-0.14)], [0.5, leafColor(0.04)], [1, leafColor(0.16)]]);
    ctx.fill();
    const r0 = at(0.05, 0), r1 = at(0.45, 0.12), r2 = at(0.85, 0.05);
    ctx.beginPath();
    ctx.moveTo(r0.x, r0.y);
    ctx.quadraticCurveTo(r1.x, r1.y, r2.x, r2.y);
    ctx.strokeStyle = 'rgba(255,255,255,0.26)';
    ctx.lineWidth = 0.7;
    ctx.stroke();
    const s0 = at(0.3, 0.5), s1 = at(0.5, 0.62), s2 = at(0.72, 0.42);
    ctx.beginPath();
    ctx.moveTo(s0.x, s0.y);
    ctx.quadraticCurveTo(s1.x, s1.y, s2.x, s2.y);
    ctx.strokeStyle = 'rgba(255,255,255,0.22)';
    ctx.lineWidth = 1;
    ctx.stroke();
  };
  ([[0.34, 14 + 5 * energy, 0.36], [0.68, 10 + 3 * energy, 0.24]] as const).forEach(([t, length, spread], index) => {
    const attach = along(t);
    const wave = index === 0 ? flutter : -flutter;
    const tilt = lean * 0.5;
    leaf(attach, tilt - Math.PI * spread - droop + wave, length);
    leaf(attach, tilt + Math.PI * spread + droop - wave, length);
  });

  // Crown: a flower when thriving, a blushing bud when content, a closed bud when tired.
  ctx.save();
  ctx.translate(tip.x, tip.y);
  ctx.rotate(lean + Math.sin(time * 1.2) * 0.06);
  if (mood === 'thriving') {
    const bloom = 0.6 + 0.4 * Math.min((energy - 0.7) / 0.25, 1) + (delighted ? 0.12 : 0);
    const length = 6.2 * bloom;
    for (let index = 0; index < 6; index += 1) {
      ctx.save();
      ctx.rotate((index / 6) * Math.PI * 2);
      ellipse(ctx, -2.4, -length - 0.6, 4.8, length + 1.2);
      ctx.fillStyle = linear(ctx, { x: 0, y: -length }, { x: 0, y: 0 }, [[0, 'rgb(255, 204, 224)'], [1, 'rgb(250, 120, 168)']]);
      ctx.fill();
      ctx.restore();
    }
    ellipse(ctx, -2.9, -2.9, 5.8, 5.8);
    ctx.fillStyle = radial(ctx, { x: -0.8, y: -0.8 }, 3.4, [[0, 'rgb(255, 237, 140)'], [1, 'rgb(250, 179, 51)']]);
    ctx.fill();
    for (let angle = 0; angle < Math.PI * 2 - 0.01; angle += (Math.PI * 2) / 5) {
      ellipse(ctx, Math.cos(angle) * 1.4 - 0.35, Math.sin(angle) * 1.4 - 0.35, 0.7, 0.7);
      ctx.fillStyle = 'rgba(191, 107, 26, 0.7)';
      ctx.fill();
    }
  } else if (mood === 'content') {
    ellipse(ctx, -3.4, -7.4, 6.8, 8.4);
    ctx.fillStyle = leafColor(0.02);
    ctx.fill();
    ellipse(ctx, -2, -8, 4, 3.6);
    ctx.fillStyle = 'rgb(255, 153, 191)';
    ctx.fill();
  } else {
    ellipse(ctx, -2.9, -6.4, 5.8, 7.2);
    ctx.fillStyle = leafColor(-0.04);
    ctx.fill();
  }
  ctx.restore();

  // Pot
  const potBody = () => {
    ctx.beginPath();
    ctx.moveTo(25, 64);
    ctx.lineTo(75, 64);
    ctx.bezierCurveTo(75.5, 76, 71, 89, 66.5, 93);
    ctx.quadraticCurveTo(50, 96.5, 33.5, 93);
    ctx.bezierCurveTo(29, 89, 24.5, 76, 25, 64);
    ctx.closePath();
  };
  potBody();
  ctx.fillStyle = linear(ctx, { x: 50, y: 64 }, { x: 50, y: 95 }, [[0, TERRACOTTA], [1, TERRACOTTA_DEEP]]);
  ctx.fill();
  ctx.save();
  potBody();
  ctx.clip();
  ctx.fillStyle = linear(ctx, { x: 25, y: 74 }, { x: 75, y: 74 }, [[0, 'rgba(255,255,255,0.22)'], [0.4, 'rgba(255,255,255,0)'], [1, 'rgba(0,0,0,0.3)']]);
  ctx.fillRect(20, 60, 60, 40);
  ctx.fillStyle = linear(ctx, { x: 50, y: 64 }, { x: 50, y: 67.5 }, [[0, 'rgba(0,0,0,0.3)'], [1, 'rgba(0,0,0,0)']]);
  ctx.fillRect(20, 64, 60, 3.5);
  ctx.fillStyle = 'rgba(153, 74, 51, 0.75)';
  ctx.fillRect(20, 87, 60, 3);
  for (let x = 29; x <= 71; x += 6) {
    ellipse(ctx, x - 0.8, 87.7, 1.6, 1.6);
    ctx.fillStyle = CREAM;
    ctx.fill();
  }
  ellipse(ctx, 27.4, 68, 5, 15);
  ctx.fillStyle = radial(ctx, { x: 29.9, y: 72 }, 8, [[0, 'rgba(255,255,255,0.26)'], [1, 'rgba(255,255,255,0)']]);
  ctx.fill();
  ctx.restore();

  ctx.beginPath();
  ctx.roundRect(21, 55.5, 58, 10, 5);
  ctx.fillStyle = linear(ctx, { x: 50, y: 55.5 }, { x: 50, y: 65.5 }, [[0, TERRACOTTA_LIGHT], [0.5, TERRACOTTA], [1, TERRACOTTA_DEEP]]);
  ctx.fill();
  ctx.fillStyle = linear(ctx, { x: 21, y: 60 }, { x: 79, y: 60 }, [[0, 'rgba(255,255,255,0.16)'], [0.4, 'rgba(255,255,255,0)'], [1, 'rgba(0,0,0,0.24)']]);
  ctx.fill();
  ctx.beginPath();
  ctx.moveTo(26, 57);
  ctx.lineTo(52, 57);
  ctx.strokeStyle = linear(ctx, { x: 26, y: 57 }, { x: 52, y: 57 }, [[0, 'rgba(255,255,255,0.5)'], [1, 'rgba(255,255,255,0)']]);
  ctx.lineWidth = 0.9;
  ctx.stroke();
  ellipse(ctx, 25.5, 54.6, 49, 5.2);
  ctx.fillStyle = linear(ctx, { x: 50, y: 54.6 }, { x: 50, y: 59.8 }, [[0, 'rgb(51, 31, 23)'], [1, 'rgb(84, 54, 36)']]);
  ctx.fill();
  for (const [x, y, w, h] of [[36, 56.4, 2.4, 1.3], [60, 56.8, 1.8, 1.1]]) {
    ellipse(ctx, x, y, w, h);
    ctx.fillStyle = 'rgb(128, 92, 69)';
    ctx.fill();
  }

  // Face, turned a little towards the pointer.
  ctx.save();
  ctx.translate(gaze.x * 1.2, gaze.y * 0.8);
  if (energy >= 0.45 || delighted) {
    for (const x of [34.2, 65.8]) {
      ellipse(ctx, x - 4.2, 78.6, 8.4, 5);
      ctx.fillStyle = radial(ctx, { x, y: 81.1 }, 4.2, [[0, `rgba(255, 122, 133, ${delighted ? 0.6 : 0.42})`], [1, 'rgba(255, 122, 133, 0)']]);
      ctx.fill();
    }
  }
  for (const x of [41.5, 58.5]) {
    if (delighted) {
      ctx.beginPath();
      ctx.moveTo(x - 3, 76.5);
      ctx.quadraticCurveTo(x, 71, x + 3, 76.5);
      ctx.strokeStyle = INK;
      ctx.lineWidth = 1.8;
      ctx.stroke();
      continue;
    }
    const blinking = time > 0 && time % 4.3 < 0.13;
    const lid = blinking ? 0.12 : mood === 'wilting' ? 0.42 : mood === 'droopy' ? 0.68 : 1;
    const eyeHeight = 7.4 * lid;
    const top = 78.7 - eyeHeight;
    ellipse(ctx, x - 3.1, top, 6.2, eyeHeight);
    ctx.fillStyle = INK;
    ctx.fill();
    if (lid > 0.3) {
      ellipse(ctx, x - 1.9 + gaze.x * 0.9, top + 1.1 + gaze.y * 0.7 * lid, 2.6, 2.6 * Math.min(lid * 1.2, 1));
      ctx.fillStyle = 'rgba(255,255,255,0.95)';
      ctx.fill();
      if (lid > 0.6) {
        ellipse(ctx, x + 1 + gaze.x * 0.9, top + eyeHeight - 2.6, 1.2, 1.2);
        ctx.fillStyle = 'rgba(255,255,255,0.7)';
        ctx.fill();
      }
    }
  }
  if (!delighted && (mood === 'droopy' || mood === 'wilting')) {
    const raise = mood === 'wilting' ? 1.4 : 0.7;
    for (const [outer, inner] of [[37.8, 44.6], [62.2, 55.4]]) {
      ctx.beginPath();
      ctx.moveTo(outer, 70.6);
      ctx.lineTo(inner, 70.6 - raise);
      ctx.strokeStyle = 'rgba(43, 20, 15, 0.85)';
      ctx.lineWidth = 1.2;
      ctx.stroke();
    }
  }
  ctx.strokeStyle = INK;
  ctx.lineWidth = 1.6;
  if (delighted || mood === 'thriving') {
    const depth = delighted ? 6.6 : 5.2;
    const mouth = () => {
      ctx.beginPath();
      ctx.moveTo(45.2, 81.2);
      ctx.quadraticCurveTo(50, 82, 54.8, 81.2);
      ctx.quadraticCurveTo(50, 81.2 + depth * 1.3, 45.2, 81.2);
      ctx.closePath();
    };
    mouth();
    ctx.fillStyle = INK;
    ctx.fill();
    ctx.save();
    mouth();
    ctx.clip();
    ellipse(ctx, 47, 81.2 + depth * 0.5, 6, 4);
    ctx.fillStyle = 'rgb(255, 120, 128)';
    ctx.fill();
    ctx.restore();
  } else {
    ctx.beginPath();
    if (mood === 'content') {
      ctx.moveTo(45.5, 82);
      ctx.quadraticCurveTo(50, 85.6, 54.5, 82);
    } else if (mood === 'droopy') {
      ctx.moveTo(46.8, 83);
      ctx.quadraticCurveTo(50, 82.4, 53.2, 83);
    } else {
      ctx.moveTo(45.5, 84.4);
      ctx.bezierCurveTo(47.5, 81, 52.5, 81, 54.5, 84.4);
    }
    ctx.stroke();
  }
  ctx.restore();

  // A bead of sweat when tired.
  if (!delighted && (mood === 'droopy' || mood === 'wilting')) {
    const slide = time === 0 ? 0 : (time * 0.5) % 1;
    const center = { x: 66.5, y: 68 + slide * 4 };
    ctx.globalAlpha = 1 - Math.max(slide - 0.7, 0) / 0.3;
    dropPath(ctx, center, 4.6);
    ctx.fillStyle = linear(ctx, { x: center.x, y: center.y - 3 }, { x: center.x, y: center.y + 2 }, [[0, 'rgb(204, 242, 255)'], [1, 'rgb(115, 191, 255)']]);
    ctx.fill();
    ctx.globalAlpha = 1;
  }
  ctx.restore();

  // A dry leaf lets go every few seconds.
  if (mood === 'wilting' && time > 0) {
    const cycle = 5.5;
    const progress = (time % cycle) / cycle;
    if (progress < 0.75) {
      const fall = progress / 0.75;
      ctx.save();
      ctx.globalAlpha = 1 - Math.max(fall - 0.6, 0) / 0.4;
      ctx.translate(tip.x + 4 + fall * 8 + Math.sin(fall * 9) * 3, tip.y + 2 + fall * 30);
      ctx.rotate(fall * 5);
      ellipse(ctx, -2.6, -1.2, 5.2, 2.4);
      ctx.fillStyle = 'rgb(179, 140, 77)';
      ctx.fill();
      ctx.restore();
    }
  }

  if (scene.thirsty) {
    const center = { x: 82, y: 44 + Math.sin(time * 2.4) * 1.3 };
    dropPath(ctx, center, 9);
    ctx.fillStyle = linear(ctx, { x: center.x, y: center.y - 5 }, { x: center.x, y: center.y + 4 }, [[0, 'rgb(158, 224, 255)'], [1, 'rgb(51, 140, 245)']]);
    ctx.fill();
    ellipse(ctx, center.x - 2, center.y - 0.6, 1.5, 2.2);
    ctx.fillStyle = 'rgba(255,255,255,0.75)';
    ctx.fill();
  }

  if (scene.splash !== null) {
    const fade = 1 - Math.max(scene.splash - 0.75, 0) / 0.25;
    [41, 50, 59].forEach((x, index) => {
      const delay = index * 0.12;
      const local = clamp((scene.splash! - delay) / (1 - delay));
      const center = { x, y: 16 + local * local * 40 };
      dropPath(ctx, center, 6);
      ctx.fillStyle = `rgba(115, 199, 255, ${fade})`;
      ctx.fill();
    });
  }

  if (reaction !== null) {
    for (let index = 0; index < 3; index += 1) {
      const local = clamp((reaction - index * 0.13) / 0.7);
      if (local <= 0 || local >= 1) continue;
      const center = { x: 50 + (index - 1) * 13 + Math.sin(local * 6 + index) * 2, y: 40 - local * 22 };
      const size = 4.2 * Math.min(local * 4, 1);
      ctx.globalAlpha = 1 - Math.max(local - 0.55, 0) / 0.45;
      heartPath(ctx, center, size);
      ctx.fillStyle = linear(ctx, { x: center.x, y: center.y - size }, { x: center.x, y: center.y + size }, [[0, 'rgb(255, 153, 179)'], [1, 'rgb(245, 77, 122)']]);
      ctx.fill();
      ctx.globalAlpha = 1;
    }
  }
}
