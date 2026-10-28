// The header's two behaviours that need a script; without it the header simply stays open and the menu still works.
// - The wordmark folds to "S" and the ring once you leave the top of the page, and unfolds again only back at the top.
//   This is the site's one scroll listener: passive, and at most one update a frame.
// - The menu (a <details>) opens and closes with its animation: a <details> drops its content the instant it closes, so
//   closing first plays the curtain back up (.closing) and only then shuts. It also closes on Escape and keeps keyboard
//   focus inside while it's open.
const header = document.querySelector<HTMLElement>('[data-header]');
const menu = document.querySelector<HTMLDetailsElement>('[data-menu]');

if (header) {
  let queued = false;
  const update = () => {
    queued = false;
    const y = window.scrollY;
    header.classList.toggle('scrolled', y > 8);
    if (menu?.open) return;
    header.classList.toggle('folded', y > 64);
  };
  window.addEventListener(
    'scroll',
    () => {
      if (!queued) {
        queued = true;
        requestAnimationFrame(update);
      }
    },
    { passive: true },
  );
  update();
}

if (menu) {
  const summary = menu.querySelector('summary')!;
  const panel = menu.querySelector<HTMLElement>('.menu-panel')!;
  const close = () => {
    if (!menu.open || menu.classList.contains('closing')) return;
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
      menu.open = false;
      return;
    }
    menu.classList.add('closing');
    const done = (e: AnimationEvent) => {
      if (e.target !== panel) return; // the items' own animations bubble up too
      panel.removeEventListener('animationend', done);
      menu.classList.remove('closing');
      menu.open = false;
    };
    panel.addEventListener('animationend', done);
  };
  summary.addEventListener('click', (e) => {
    if (!menu.open) return; // opening is the <details> itself; its CSS plays the way in
    e.preventDefault();
    close();
  });
  // A link inside closes the menu as you leave, so going back doesn't land on it open.
  panel.addEventListener('click', (e) => {
    if ((e.target as Element).closest('a[href^="#"]')) close();
  });
  menu.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && menu.open) {
      close();
      summary.focus();
      return;
    }
    if (e.key !== 'Tab' || !menu.open) return;
    const focusable = [...menu.querySelectorAll<HTMLElement>('summary, a[href]')].filter((el) => el.offsetParent !== null);
    const first = focusable[0];
    const lastEl = focusable[focusable.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      lastEl?.focus();
    } else if (!e.shiftKey && document.activeElement === lastEl) {
      e.preventDefault();
      first?.focus();
    }
  });
}
