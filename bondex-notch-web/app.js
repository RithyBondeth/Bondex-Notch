/* Bondex Notch — marketing site behaviour.
   No dependencies. Everything degrades to a static page without JS. */

(() => {
  'use strict';

  const prefersReducedMotion =
    window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ── Sticky nav hairline ─────────────────────────────── */

  const nav = document.getElementById('nav');
  if (nav) {
    const onScroll = () => nav.classList.toggle('is-stuck', window.scrollY > 8);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
  }

  /* ── Interactive notch demo ──────────────────────────── */

  const notch = document.getElementById('notch');
  const hint = document.getElementById('stageHint');
  if (!notch) return;

  const STATES = { COLLAPSED: 'collapsed', PEEK: 'peek', EXPANDED: 'expanded' };

  // Mirrors the app: the panel falls back to a peek while "media is playing",
  // and only fully closes when nothing is live.
  let idleState = STATES.PEEK;
  let isPinned = false;
  let closeTimer = null;
  let hasInteracted = false;

  const setState = (state) => {
    notch.dataset.state = state;
    notch.setAttribute('aria-expanded', String(state === STATES.EXPANDED));
  };

  const expand = () => {
    clearTimeout(closeTimer);
    setState(STATES.EXPANDED);
    if (!hasInteracted) {
      hasInteracted = true;
      hint?.classList.add('is-hidden');
    }
  };

  const scheduleClose = () => {
    clearTimeout(closeTimer);
    closeTimer = setTimeout(() => {
      if (!isPinned) setState(idleState);
    }, 260);
  };

  notch.addEventListener('mouseenter', expand);
  notch.addEventListener('mouseleave', () => {
    if (!isPinned) scheduleClose();
  });

  // Click pins it open, matching the app's behaviour.
  notch.addEventListener('click', (event) => {
    // Tab chips handle their own clicks.
    if (event.target.closest('.chip')) return;

    if (notch.dataset.state === STATES.EXPANDED && isPinned) {
      isPinned = false;
      setState(idleState);
    } else {
      isPinned = true;
      expand();
    }
  });

  notch.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      notch.click();
    } else if (event.key === 'Escape') {
      isPinned = false;
      setState(idleState);
    }
  });

  notch.addEventListener('focus', expand);
  notch.addEventListener('blur', () => {
    if (!isPinned) scheduleClose();
  });

  /* ── Panel tabs ──────────────────────────────────────── */

  const chips = Array.from(notch.querySelectorAll('.chip'));
  const views = Array.from(notch.querySelectorAll('.view'));

  const selectTab = (name) => {
    chips.forEach((chip) => {
      const active = chip.dataset.tab === name;
      chip.classList.toggle('is-active', active);
      chip.setAttribute('aria-selected', String(active));
    });
    views.forEach((view) => {
      view.classList.toggle('is-active', view.dataset.view === name);
    });
  };

  chips.forEach((chip) => {
    chip.addEventListener('click', (event) => {
      event.stopPropagation();
      isPinned = true;
      selectTab(chip.dataset.tab);
    });
  });

  /* ── Ambient demo loop ───────────────────────────────── */

  // Before anyone touches it, cycle collapsed → peek so the shape reads as a
  // live product rather than a screenshot. Stops for good on first interaction,
  // and never runs when reduced motion is requested.
  if (!prefersReducedMotion) {
    let phase = 0;
    const ambient = setInterval(() => {
      if (hasInteracted) {
        clearInterval(ambient);
        return;
      }
      phase = (phase + 1) % 2;
      idleState = phase === 0 ? STATES.COLLAPSED : STATES.PEEK;
      setState(idleState);
    }, 3200);
  }

  setState(idleState);
  selectTab('home');
})();
