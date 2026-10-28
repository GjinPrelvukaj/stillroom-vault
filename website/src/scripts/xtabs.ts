// "Inside the app" tabs (after Skiper UI's 96 Expandable tabs): icons that open to show their name, and screens that
// slide in from the side you move towards while the box's height follows. A real tablist: arrows, Home and End move
// between tabs. Without scripts the first screen shows; with reduced motion screens swap at once.
import { gsap, reduced, springs } from './gsap';

const calm = reduced();

document.querySelectorAll<HTMLElement>('[data-xtabs]').forEach((list) => {
  const tabs = [...list.querySelectorAll<HTMLButtonElement>('[role="tab"]')];
  const panels = tabs.map((t) => document.getElementById(t.getAttribute('aria-controls') ?? '')!);
  const stage = panels[0]?.closest<HTMLElement>('[data-xtabs-stage]');
  if (!stage) return;
  let current = Math.max(0, tabs.findIndex((t) => t.getAttribute('aria-selected') === 'true'));
  let moving: gsap.core.Timeline | null = null;

  const choose = (i: number, focus = false) => {
    if (focus) tabs[i]!.focus();
    if (i === current) return;
    moving?.progress(1); // a click mid-slide finishes the last one first
    const dir = i > current ? 1 : -1;
    const from = panels[current]!;
    const to = panels[i]!;
    current = i;
    tabs.forEach((t, k) => {
      t.setAttribute('aria-selected', String(k === i));
      t.tabIndex = k === i ? 0 : -1;
    });
    if (calm) {
      from.hidden = true;
      to.hidden = false;
      return;
    }
    const before = stage.offsetHeight;
    stage.classList.add('moving');
    from.classList.add('leaving');
    to.hidden = false;
    const after = stage.offsetHeight;
    const { duration, ease } = springs.appear;
    moving = gsap
      .timeline({
        onComplete: () => {
          from.hidden = true;
          from.classList.remove('leaving');
          stage.classList.remove('moving');
          gsap.set([stage, from, to], { clearProps: 'height,transform,opacity' });
          moving = null;
        },
      })
      .fromTo(stage, { height: before }, { height: after, duration: duration * 1.3, ease }, 0)
      .fromTo(to, { x: 56 * dir, opacity: 0 }, { x: 0, opacity: 1, duration: duration * 1.3, ease }, 0)
      .to(from, { x: -56 * dir, opacity: 0, duration: duration * 0.8, ease }, 0);
  };

  tabs.forEach((t, i) => {
    t.addEventListener('click', () => choose(i));
    t.addEventListener('keydown', (e) => {
      const n = tabs.length;
      const keys: Record<string, number> = { ArrowRight: i + 1, ArrowDown: i + 1, ArrowLeft: i - 1 + n, ArrowUp: i - 1 + n, Home: 0, End: n - 1 };
      const next = keys[e.key];
      if (next === undefined) return;
      e.preventDefault();
      choose(next % n, true);
    });
  });
});
