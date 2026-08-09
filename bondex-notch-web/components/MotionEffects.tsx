'use client';

import { useEffect } from 'react';

type Cleanup = () => void;

const revealGroups = [
  '.hero .label, .hero__lede, .hero .actions, .hero .meta, .hero__signals, .stage',
  '.showcase__head > *, .trust-item',
  '.efficiency__copy > *, .efficiency__fact',
  '.slab__head > *, .feature',
  '#how .head > *, .state, .callout',
  '.plan',
  '#faq .slab__head > *, .qa',
  '.section--cta .label, .section--cta .title, .section--cta .lede, .section--cta .actions, .section--cta .meta',
  '.footer__inner > *, .footer__bottom > *',
];

/**
 * Progressive motion layer. The page remains fully visible without JavaScript;
 * reveal styles are enabled only after every target has been annotated.
 */
export default function MotionEffects() {
  useEffect(() => {
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    if (reducedMotion.matches) return;

    const root = document.documentElement;
    const cleanups: Cleanup[] = [];
    const revealTargets = new Set<HTMLElement>();

    revealGroups.forEach((selector) => {
      document.querySelectorAll<HTMLElement>(selector).forEach((element, index) => {
        element.dataset.reveal = '';
        element.style.setProperty('--reveal-delay', `${(index % 6) * 65}ms`);
        revealTargets.add(element);
      });
    });

    document.querySelectorAll<HTMLElement>('.story').forEach((story, index) => {
      const copy = story.querySelector<HTMLElement>('.story__copy');
      const visual = story.querySelector<HTMLElement>('.product-shot, .settings-shot, .app-preview-board');
      const copyDirection = index % 2 === 0 ? '-34px' : '34px';

      if (copy) {
        copy.dataset.reveal = '';
        copy.style.setProperty('--reveal-x', copyDirection);
        revealTargets.add(copy);
      }

      if (visual) {
        visual.dataset.reveal = '';
        visual.style.setProperty('--reveal-x', index % 2 === 0 ? '34px' : '-34px');
        visual.style.setProperty('--reveal-delay', '110ms');
        revealTargets.add(visual);
      }
    });

    root.dataset.motionReady = 'true';

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          (entry.target as HTMLElement).classList.add('is-visible');
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: '0px 0px -8% 0px', threshold: 0.12 },
    );

    revealTargets.forEach((element) => observer.observe(element));
    cleanups.push(() => observer.disconnect());

    let scrollFrame = 0;
    const updateScroll = () => {
      scrollFrame = 0;
      const maxScroll = Math.max(document.documentElement.scrollHeight - window.innerHeight, 1);
      const progress = Math.min(window.scrollY / maxScroll, 1);
      root.style.setProperty('--page-progress', `${progress * 100}%`);
      root.style.setProperty('--field-scroll', `${Math.max(-28, window.scrollY * -0.018)}px`);
    };
    const onScroll = () => {
      if (!scrollFrame) scrollFrame = window.requestAnimationFrame(updateScroll);
    };
    updateScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    cleanups.push(() => {
      window.removeEventListener('scroll', onScroll);
      window.cancelAnimationFrame(scrollFrame);
    });

    if (window.matchMedia('(hover: hover) and (pointer: fine)').matches) {
      let pointerFrame = 0;
      let pointerX = window.innerWidth / 2;
      let pointerY = window.innerHeight / 2;

      const updatePointer = () => {
        pointerFrame = 0;
        const x = pointerX / window.innerWidth;
        const y = pointerY / window.innerHeight;
        root.style.setProperty('--field-x', `${(x - 0.5) * -18}px`);
        root.style.setProperty('--field-y', `${(y - 0.5) * -12}px`);
        root.style.setProperty('--spot-x', `${x * 100}%`);
        root.style.setProperty('--spot-y', `${y * 100}%`);
      };
      const onPointerMove = (event: PointerEvent) => {
        pointerX = event.clientX;
        pointerY = event.clientY;
        if (!pointerFrame) pointerFrame = window.requestAnimationFrame(updatePointer);
      };
      window.addEventListener('pointermove', onPointerMove, { passive: true });
      cleanups.push(() => {
        window.removeEventListener('pointermove', onPointerMove);
        window.cancelAnimationFrame(pointerFrame);
      });

      document
        .querySelectorAll<HTMLElement>('.product-shot:not(.real-product), .settings-shot, .plan--featured')
        .forEach((element) => {
          element.dataset.motionTilt = '';
          const move = (event: PointerEvent) => {
            const bounds = element.getBoundingClientRect();
            const x = (event.clientX - bounds.left) / bounds.width;
            const y = (event.clientY - bounds.top) / bounds.height;
            element.style.setProperty('--tilt-x', `${(0.5 - y) * 5}deg`);
            element.style.setProperty('--tilt-y', `${(x - 0.5) * 6}deg`);
            element.style.setProperty('--glow-x', `${x * 100}%`);
            element.style.setProperty('--glow-y', `${y * 100}%`);
          };
          const reset = () => {
            element.style.setProperty('--tilt-x', '0deg');
            element.style.setProperty('--tilt-y', '0deg');
            element.style.setProperty('--glow-x', '50%');
            element.style.setProperty('--glow-y', '50%');
          };
          element.addEventListener('pointermove', move, { passive: true });
          element.addEventListener('pointerleave', reset, { passive: true });
          cleanups.push(() => {
            element.removeEventListener('pointermove', move);
            element.removeEventListener('pointerleave', reset);
          });
        });

      document.querySelectorAll<HTMLElement>('.actions .btn').forEach((button) => {
        const move = (event: PointerEvent) => {
          const bounds = button.getBoundingClientRect();
          const x = event.clientX - (bounds.left + bounds.width / 2);
          const y = event.clientY - (bounds.top + bounds.height / 2);
          button.style.setProperty('--magnetic-x', `${x * 0.12}px`);
          button.style.setProperty('--magnetic-y', `${y * 0.16}px`);
        };
        const reset = () => {
          button.style.setProperty('--magnetic-x', '0px');
          button.style.setProperty('--magnetic-y', '0px');
        };
        button.addEventListener('pointermove', move, { passive: true });
        button.addEventListener('pointerleave', reset, { passive: true });
        cleanups.push(() => {
          button.removeEventListener('pointermove', move);
          button.removeEventListener('pointerleave', reset);
        });
      });

      document.querySelectorAll<HTMLElement>('.story').forEach((story) => {
        const move = (event: PointerEvent) => {
          const bounds = story.getBoundingClientRect();
          story.style.setProperty('--story-x', `${event.clientX - bounds.left}px`);
          story.style.setProperty('--story-y', `${event.clientY - bounds.top}px`);
        };
        story.addEventListener('pointermove', move, { passive: true });
        cleanups.push(() => story.removeEventListener('pointermove', move));
      });
    }

    return () => {
      cleanups.forEach((cleanup) => cleanup());
      delete root.dataset.motionReady;
    };
  }, []);

  return null;
}
