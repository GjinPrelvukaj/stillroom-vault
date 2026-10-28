// Disclosures that expand and collapse ([data-glide] on a <details>): the content's height eases open, and on closing
// eases shut before the <details> actually closes. Done here rather than in CSS because only some browsers can
// animate a <details> by CSS alone. Without scripts it simply opens and closes; with reduced motion, too.
const reduced = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

document.querySelectorAll<HTMLDetailsElement>('details[data-glide]').forEach((details) => {
  const summary = details.querySelector('summary');
  const body = summary?.nextElementSibling as HTMLElement | null;
  if (!summary || !body) return;
  let running: Animation | null = null;

  summary.addEventListener('click', (e) => {
    if (reduced()) return;
    e.preventDefault();
    const ease = getComputedStyle(details).getPropertyValue('--spring-change').trim() || 'ease';
    // The spring's length, as the browser gives it back: "407ms" or ".407s".
    const dur = getComputedStyle(details).getPropertyValue('--spring-change-dur').trim();
    const duration = (parseFloat(dur) || 0.4) * (dur.endsWith('ms') ? 1 : 1000);
    // The body's box, padding included, so it can shrink to nothing and grow back to its full size.
    const box = (h: number, pt: string, pb: string) => ({ height: `${h}px`, paddingTop: pt, paddingBottom: pb });
    const now = getComputedStyle(body);
    const from = running || details.open ? box(parseFloat(now.height), now.paddingTop, now.paddingBottom) : box(0, '0px', '0px');
    running?.cancel();
    const opening = !details.open || details.dataset.closing === '1';
    if (opening) {
      delete details.dataset.closing;
      details.open = true;
    } else {
      details.dataset.closing = '1';
    }
    const full = getComputedStyle(body);
    const to = opening ? box(parseFloat(full.height), full.paddingTop, full.paddingBottom) : box(0, '0px', '0px');
    body.style.overflow = 'clip';
    running = body.animate([from, to], { duration, easing: ease });
    running.onfinish = () => {
      running = null;
      body.style.overflow = '';
      if (!opening) {
        details.open = false;
        delete details.dataset.closing;
      }
    };
  });
});
