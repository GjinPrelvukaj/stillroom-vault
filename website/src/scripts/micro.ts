// Small, exact motions shared across pages. Each only adds to a page that already reads correctly without it.
// - Rolling numbers ([data-roll]): digits roll into place like an odometer when they come into view, and roll() moves
//   them later (the network panel). The number stays real text for screen readers; the rolling columns are hidden.
// - Star border (.star-border): one point of light goes once round the outline when it comes into view, then rests.
import { reduced } from './gsap';

const calm = reduced();

/** Shows `value` in `el` as rolling digit columns. */
export function roll(el: HTMLElement, value: number | string) {
  const text = String(value);
  let strip = el.querySelector<HTMLElement>('.roll');
  if (!strip) {
    el.textContent = '';
    // The number as real text for screen readers; the rolling columns are only for the eye.
    const said = document.createElement('span');
    said.className = 'visually-hidden roll-said';
    strip = document.createElement('span');
    strip.className = 'roll';
    strip.setAttribute('aria-hidden', 'true');
    el.append(said, strip);
  }
  el.querySelector<HTMLElement>('.roll-said')!.textContent = text;
  // One column per character; digits roll, anything else (a colon) is set as it is.
  while (strip.children.length < text.length) {
    const col = document.createElement('span');
    col.className = 'roll-col';
    col.innerHTML = '<span class="roll-digits">0<br>1<br>2<br>3<br>4<br>5<br>6<br>7<br>8<br>9</span>';
    strip.append(col);
  }
  while (strip.children.length > text.length) strip.lastElementChild!.remove();
  [...strip.children].forEach((col, i) => {
    const ch = text[i]!;
    const digits = col.firstElementChild as HTMLElement;
    if (/\d/.test(ch)) {
      col.classList.remove('roll-char');
      digits.innerHTML = '0<br>1<br>2<br>3<br>4<br>5<br>6<br>7<br>8<br>9';
      digits.style.transform = `translateY(${-Number(ch)}em)`;
    } else {
      col.classList.add('roll-char');
      digits.textContent = ch;
      digits.style.transform = 'none';
    }
  });
}

const seen = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      const el = entry.target as HTMLElement;
      seen.unobserve(el);
      if (el.matches('[data-roll]')) {
        const final = el.dataset.roll || el.textContent || '';
        roll(el, final.replace(/\d/g, '0'));
        requestAnimationFrame(() => requestAnimationFrame(() => roll(el, final)));
      } else el.classList.add('go');
    }
  },
  { threshold: 0.6 },
);

if (!calm) {
  document.querySelectorAll<HTMLElement>('[data-roll]').forEach((el) => {
    el.dataset.roll = el.textContent?.trim() ?? '';
    seen.observe(el);
  });
  document.querySelectorAll<HTMLElement>('.star-border').forEach((el) => seen.observe(el));
}
