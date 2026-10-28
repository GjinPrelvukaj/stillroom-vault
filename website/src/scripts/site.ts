// What every page does once scripts run. Everything here only adds to a page that already works without it.
import { gsap, HEX, reduced, ScrollTrigger, SplitText, springs } from './gsap';
import './micro';

const calm = reduced();

/* Segments: the lit pill slides to the chosen option. Works as tabs (role=tab) or as a radio group. */
export function placePill(group: HTMLElement) {
  const pill = group.querySelector<HTMLElement>('.pill');
  const chosen = group.querySelector<HTMLElement>('[aria-selected="true"], [aria-checked="true"]');
  if (!pill || !chosen) return;
  pill.style.width = `${chosen.offsetWidth}px`;
  pill.style.transform = `translateX(${chosen.offsetLeft}px)`;
  group.classList.add('measured');
}

function segments() {
  document.querySelectorAll<HTMLElement>('.segments').forEach((group) => {
    const buttons = [...group.querySelectorAll<HTMLButtonElement>('button')];
    const isTabs = group.getAttribute('role') === 'tablist';
    const attr = isTabs ? 'aria-selected' : 'aria-checked';

    const choose = (button: HTMLButtonElement, focus = false) => {
      buttons.forEach((b) => {
        const on = b === button;
        b.setAttribute(attr, String(on));
        b.tabIndex = on ? 0 : -1;
        const panelId = b.getAttribute('aria-controls');
        if (isTabs && panelId) {
          const panel = document.getElementById(panelId);
          if (panel) panel.hidden = !on;
        }
      });
      if (focus) button.focus();
      placePill(group);
      group.dispatchEvent(new CustomEvent('segment-change', { detail: button.dataset.value ?? button.id }));
    };

    buttons.forEach((b) => {
      b.addEventListener('click', () => choose(b));
      b.addEventListener('keydown', (e) => {
        const i = buttons.indexOf(b);
        const next =
          e.key === 'ArrowRight' || e.key === 'ArrowDown'
            ? buttons[(i + 1) % buttons.length]
            : e.key === 'ArrowLeft' || e.key === 'ArrowUp'
              ? buttons[(i - 1 + buttons.length) % buttons.length]
              : e.key === 'Home'
                ? buttons[0]
                : e.key === 'End'
                  ? buttons[buttons.length - 1]
                  : null;
        if (next) {
          e.preventDefault();
          choose(next, true);
        }
      });
    });
    placePill(group);
    new ResizeObserver(() => placePill(group)).observe(group);
  });
}

/* Section arrivals where the browser has no scroll-driven animations: the same rise, run by GSAP. */
function arrivalsFallback() {
  if (calm || CSS.supports('animation-timeline: view()')) return;
  const items = gsap.utils.toArray<HTMLElement>('.reveal, .stagger > *');
  const below = items.filter((el) => el.getBoundingClientRect().top > window.innerHeight);
  gsap.set(below, { opacity: 0, y: 24 });
  ScrollTrigger.batch(below, {
    start: 'top 92%',
    once: true,
    onEnter: (batch) =>
      gsap.to(batch, { opacity: 1, y: 0, duration: springs.appear.duration * 1.6, ease: springs.appear.ease, stagger: 0.07 }),
  });
}

/* Headlines rise line by line out of a mask as they come into view. */
function risingHeadlines() {
  if (calm) return;
  document.querySelectorAll<HTMLElement>('.rise').forEach((el) => {
    if (el.getBoundingClientRect().top < window.innerHeight * 0.9) return; // already on screen: leave it be
    SplitText.create(el, {
      type: 'lines',
      mask: 'lines',
      aria: 'auto',
      autoSplit: true,
      onSplit: (self) =>
        gsap.from(self.lines, {
          yPercent: 110,
          duration: 1.1,
          ease: 'expo.out',
          stagger: 0.08,
          scrollTrigger: { trigger: el, start: 'top 88%', once: true },
        }),
    });
  });
}

/* Numbers and terms that resolve out of hex as they arrive (the footer's zeros, key figures). */
function scrambles() {
  if (calm) return;
  document.querySelectorAll<HTMLElement>('[data-scramble]').forEach((el) => {
    const text = el.textContent ?? '';
    ScrollTrigger.create({
      trigger: el,
      start: 'top 95%',
      once: true,
      onEnter: () =>
        gsap.to(el, { duration: 1.1, scrambleText: { text, chars: HEX, speed: 0.5, revealDelay: 0.35 } }),
    });
  });
}

/* A link to a question (#id on a <details>, as search results and the FAQ use) opens it on arrival. */
function openLinkedQuestion() {
  const el = location.hash ? document.getElementById(decodeURIComponent(location.hash.slice(1))) : null;
  if (el instanceof HTMLDetailsElement) el.open = true;
}

segments();
openLinkedQuestion();
window.addEventListener('hashchange', openLinkedQuestion);
arrivalsFallback();
risingHeadlines();
scrambles();
