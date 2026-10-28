// The format page's terms, defined on hover, focus or tap (after Skiper UI's #101, custom tooltip). The text comes
// from docs/FORMAT.md, so the first use of each glossary term in the running text is wrapped here, never in code or
// headings. Each term is a button described by its own hidden definition, for screen readers; the floating tip is
// what's seen. Without scripts the page simply reads as written.
import { glossary } from '../lib/glossary';

const prose = document.querySelector<HTMLElement>('.prose');
if (prose) {
  const skip = 'pre, code, h1, h2, h3, h4, h5, h6, a, button';
  const left = new Set(glossary);
  const walker = document.createTreeWalker(prose, NodeFilter.SHOW_TEXT, {
    acceptNode: (n) => (n.parentElement?.closest(skip) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
  });
  const nodes: Text[] = [];
  while (walker.nextNode()) nodes.push(walker.currentNode as Text);

  for (const node of nodes) {
    let text: Text | null = node;
    while (text && left.size) {
      // The earliest unused term in this text node.
      let best: { term: (typeof glossary)[number]; at: number; len: number } | null = null;
      for (const term of left) {
        const m = term.match.exec(text.data);
        if (m && (!best || m.index < best.at)) best = { term, at: m.index, len: m[0].length };
      }
      if (!best) break;
      left.delete(best.term);
      const word = text.splitText(best.at);
      text = word.splitText(best.len);

      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'term';
      btn.dataset.term = best.term.id;
      btn.setAttribute('aria-describedby', `term-${best.term.id}`);
      btn.textContent = word.data;
      const def = document.createElement('span');
      def.id = `term-${best.term.id}`;
      def.className = 'visually-hidden';
      def.textContent = best.term.text;
      word.replaceWith(btn, def);
    }
  }

  // One floating tip, placed above the term (below when there's no room), kept inside the window.
  const tip = document.createElement('div');
  tip.className = 'term-tip';
  tip.setAttribute('aria-hidden', 'true');
  tip.hidden = true;
  const body = document.createElement('p');
  const arrow = document.createElement('span');
  arrow.className = 'term-tip-arrow';
  tip.append(body, arrow);
  document.body.append(tip);

  let open: HTMLButtonElement | null = null;
  const place = (btn: HTMLButtonElement) => {
    const r = btn.getBoundingClientRect();
    const w = tip.offsetWidth;
    const h = tip.offsetHeight;
    const gap = 10;
    const below = r.top - h - gap < 72; // no room under the sticky header: drop below the term
    const x = Math.min(Math.max(8, r.left + r.width / 2 - w / 2), window.innerWidth - w - 8);
    tip.style.left = `${x}px`;
    tip.style.top = `${below ? r.bottom + gap : r.top - h - gap}px`;
    tip.style.setProperty('--arrow-x', `${r.left + r.width / 2 - x}px`);
    tip.dataset.side = below ? 'bottom' : 'top';
  };
  const show = (btn: HTMLButtonElement) => {
    open = btn;
    body.textContent = document.getElementById(btn.getAttribute('aria-describedby') ?? '')?.textContent ?? '';
    tip.hidden = false;
    place(btn);
    tip.classList.remove('in');
    void tip.offsetWidth; // restart the entrance
    tip.classList.add('in');
  };
  const hide = () => {
    open = null;
    tip.hidden = true;
    tip.classList.remove('in');
  };

  const termOf = (e: Event) => (e.target as Element | null)?.closest<HTMLButtonElement>('button.term') ?? null;
  prose.addEventListener('pointerover', (e) => {
    const b = termOf(e);
    if (b && b !== open && (e as PointerEvent).pointerType === 'mouse') show(b);
  });
  prose.addEventListener('pointerout', (e) => {
    const b = termOf(e);
    if (b && (e as PointerEvent).pointerType === 'mouse' && document.activeElement !== b) hide();
  });
  prose.addEventListener('focusin', (e) => {
    const b = termOf(e);
    if (b && b !== open) show(b);
  });
  prose.addEventListener('focusout', (e) => {
    if (termOf(e)) hide();
  });
  // A tap shows it (Safari doesn't focus a tapped button); Enter or Space on an open one closes it.
  prose.addEventListener('click', (e) => {
    const b = termOf(e);
    if (!b) return;
    if (b !== open) show(b);
    else if ((e as MouseEvent).detail === 0) hide();
  });
  document.addEventListener('click', (e) => {
    if (open && !termOf(e)) hide();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && open) hide();
  });
  window.addEventListener('scroll', () => open && place(open), { passive: true });
  window.addEventListener('resize', () => open && hide());
}
