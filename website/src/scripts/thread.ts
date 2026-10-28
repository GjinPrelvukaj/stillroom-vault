// A thread in the margin of every long page: one violet stroke from the first stop to the last, drawn as you read
// down, a node lighting at each stop it reaches (after Skiper UI's #19, SVG follow scroll). The stops are the
// security page's eleven rules (its bold "1." to "11." lines, from docs/SECURITY.md), and on every other page its
// chapters (the text's h2s, or its h3s when it has too few). Only where the layout asks for it (`data-thread`).
// Decoration only: aria-hidden, hidden on narrow screens by CSS, drawn in full under reduced motion, and simply absent
// without scripts.
import { reduced, ScrollTrigger } from './gsap';

const SVG = 'http://www.w3.org/2000/svg';
const prose = document.querySelector<HTMLElement>('.prose[data-thread]');

/** The security page's rules, if this is that page. */
function securityRules(text: HTMLElement): HTMLElement[] {
  const start = text.querySelector<HTMLElement>('h2#rules');
  const rules: HTMLElement[] = [];
  for (let el = start?.nextElementSibling; el && el.tagName !== 'H2'; el = el.nextElementSibling) {
    const s = el.firstElementChild;
    if (el.tagName === 'P' && s?.tagName === 'STRONG' && el.textContent === s.textContent && /^\d+\.\s/.test(s.textContent ?? '')) {
      rules.push(el as HTMLElement);
    }
  }
  return rules;
}

/** Where the thread stops: the rules, or the chapters. */
function stops(text: HTMLElement): HTMLElement[] {
  const rules = securityRules(text);
  if (rules.length > 1) return rules;
  const h2 = [...text.querySelectorAll<HTMLElement>(':scope > h2')];
  return h2.length > 1 ? h2 : [...text.querySelectorAll<HTMLElement>(':scope > h2, :scope > h3')];
}

if (prose) {
  const rules = stops(prose);
  if (rules.length > 1) {
    const svg = document.createElementNS(SVG, 'svg');
    svg.classList.add('thread');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');
    const track = document.createElementNS(SVG, 'path');
    track.classList.add('thread-track');
    const line = document.createElementNS(SVG, 'path');
    line.classList.add('thread-line');
    line.setAttribute('pathLength', '1');
    svg.append(track, line);
    const nodes = rules.map(() => {
      const c = document.createElementNS(SVG, 'circle');
      c.classList.add('thread-node');
      c.setAttribute('r', '3.5');
      svg.append(c);
      return c;
    });
    prose.append(svg);

    const W = 16;
    const X = W / 2;
    let ys: number[] = [];
    let progress = reduced() ? 1 : 0;

    const paint = () => {
      const span = ys[ys.length - 1]! - ys[0]!;
      line.style.strokeDashoffset = String(1 - progress);
      nodes.forEach((n, i) => n.classList.toggle('on', progress * span >= ys[i]! - ys[0]! - 1));
    };

    // Each rule's node sits on its first line; between two, the thread bows gently to one side, then the other.
    const layout = () => {
      // offsetTop, not the rendered box, so a rule still sliding in doesn't move its node.
      ys = rules.map((r) => r.offsetTop + (parseFloat(getComputedStyle(r).lineHeight) || 24) / 2);
      const y0 = ys[0]!;
      const h = ys[ys.length - 1]! - y0;
      svg.style.top = `${y0}px`;
      svg.setAttribute('width', String(W));
      svg.setAttribute('height', String(Math.ceil(h) + 8));
      svg.setAttribute('viewBox', `0 -4 ${W} ${Math.ceil(h) + 8}`);
      let d = `M ${X} 0`;
      ys.slice(1).forEach((y, i) => {
        const a = ys[i]! - y0;
        const b = y - y0;
        const bow = i % 2 ? -4 : 4;
        d += ` C ${X + bow} ${a + (b - a) / 3} ${X + bow} ${b - (b - a) / 3} ${X} ${b}`;
      });
      track.setAttribute('d', d);
      line.setAttribute('d', d);
      nodes.forEach((n, i) => {
        n.setAttribute('cx', String(X));
        n.setAttribute('cy', String(ys[i]! - y0));
      });
      paint();
    };
    layout();

    // The stroke's head follows the reading line, 40% of the way down the window.
    const st = reduced()
      ? null
      : ScrollTrigger.create({
          trigger: svg,
          start: 'top 40%',
          end: 'bottom 40%',
          onUpdate: (self) => {
            progress = self.progress;
            paint();
          },
        });

    let raf = 0;
    new ResizeObserver(() => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        layout();
        st?.refresh();
      });
    }).observe(prose);
  }
}
