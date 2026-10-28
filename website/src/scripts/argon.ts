// The Argon2 ring fills once as it comes into view, the memory figure rolling up to 512 like an odometer: the
// stretch, drawn (after Skiper UI's #37, animated number). Reduced motion or no scripts: the ring is full and the
// figure reads 512 MB from the start.
import { gsap, reduced, springs } from './gsap';

const TO = 512;
const LINE = 1.15; // one digit's height in em, as .odo sets it in ArgonRing.astro

document.querySelectorAll<HTMLElement>('[data-argon]').forEach((root) => {
  if (reduced()) return;
  const dots = [...root.querySelectorAll<SVGCircleElement>('.dr-dot')];
  const pct = root.querySelector<HTMLElement>('[data-pct]')!;
  const r = dots[0]?.dataset.r ?? '3';
  let shown = -1;

  // One column per digit, 0 to 9 and a 0 again below, so 9 rolls on into 0. The figure is aria-hidden: the heading
  // beside it says 512 MB in words.
  const places = String(TO).length;
  pct.textContent = '';
  const cols = Array.from({ length: places }, () => {
    const cell = document.createElement('span');
    cell.className = 'odo';
    const strip = document.createElement('span');
    strip.className = 'odo-strip';
    strip.textContent = '01234567890';
    cell.append(strip);
    pct.append(cell);
    return { cell, strip };
  });
  pct.append(' MB');

  const paint = (p: number) => {
    const on = Math.ceil(dots.length * p);
    if (on !== shown) {
      shown = on;
      dots.forEach((d, i) => {
        d.classList.toggle('on', i < on);
        const edge = i === on - 1 && on < dots.length;
        d.classList.toggle('edge', edge);
        d.setAttribute('r', String(edge ? Number(r) * 1.6 : Number(r)));
      });
    }
    const v = TO * p;
    cols.forEach(({ cell, strip }, i) => {
      const k = places - 1 - i; // 0 for units
      const whole = Math.floor(v / 10 ** k);
      // Units roll continuously; a higher digit only turns while the one below it rolls from 9 to 0.
      const below = k === 0 ? v - Math.floor(v) : (v / 10 ** (k - 1)) % 10;
      const pos = (whole % 10) + (k === 0 ? below : Math.max(0, below - 9));
      strip.style.transform = `translateY(${-pos * LINE}em)`;
      cell.classList.toggle('lead', k > 0 && v < 10 ** k);
    });
  };
  paint(0);

  const counter = { p: 0 };
  const io = new IntersectionObserver(
    ([e]) => {
      if (!e?.isIntersecting) return;
      io.disconnect();
      gsap.to(counter, {
        p: 1,
        duration: springs.drift.duration * 1.6,
        // The spring overshoots a touch; a memory figure shouldn't read 517, so it stops at 512.
        ease: (t: number) => Math.min(1, springs.drift.ease(t)),
        onUpdate: () => paint(counter.p),
      });
    },
    { threshold: 0.5 },
  );
  io.observe(pct);
});
