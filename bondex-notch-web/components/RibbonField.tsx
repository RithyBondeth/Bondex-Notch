'use client';

import { useEffect, useRef } from 'react';
import { renderRibbonField } from '@/lib/ribbonField';

/**
 * The wallpaper. The canvas holds the waved stripe field; the grain and
 * vignette are pseudo-elements on `.field` in globals.css, so they blend with
 * the canvas rather than with the page.
 *
 * The field is static (`animated: false` in the source parameters), so it
 * paints once on mount and again on a debounced resize.
 */
export default function RibbonField() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    let lastW = 0;
    let lastH = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;

    const draw = () => {
      lastW = window.innerWidth;
      lastH = window.innerHeight;
      renderRibbonField(canvas, lastW, lastH);
    };

    const onResize = () => {
      // Mobile browsers fire resize as the URL bar hides. Re-rendering a
      // full-screen field for a 60px height change is not worth it.
      if (
        window.innerWidth === lastW &&
        Math.abs(window.innerHeight - lastH) < 120
      ) {
        return;
      }
      clearTimeout(timer);
      timer = setTimeout(draw, 180);
    };

    draw();
    window.addEventListener('resize', onResize, { passive: true });

    return () => {
      clearTimeout(timer);
      window.removeEventListener('resize', onResize);
    };
  }, []);

  return (
    <div className="field" aria-hidden="true">
      <canvas ref={canvasRef} />
      <div className="field__aurora" />
      <div className="field__orbit field__orbit--one" />
      <div className="field__orbit field__orbit--two" />
      <div className="field__starlight" />
    </div>
  );
}
