'use client';

import { type RefObject, useEffect, useState } from 'react';

/**
 * The panel is drawn at the app's own size, one pixel per point. Where its
 * container is narrower than that, it is zoomed down as a whole — the way a
 * smaller screenshot would be — rather than reflowed into a layout the app
 * never has.
 */
export default function useFitZoom(ref: RefObject<HTMLElement | null>, width: number, floor = 0.45) {
  const [zoom, setZoom] = useState(1);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => {
      const available = entry.contentRect.width;
      setZoom(Math.max(Math.min(available / width, 1), floor));
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, [ref, width, floor]);

  return zoom;
}
