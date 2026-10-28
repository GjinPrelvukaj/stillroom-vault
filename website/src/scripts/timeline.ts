// The changelog as a timeline (after Skiper UI's #74, timeline calendar): each version a marker on the line beside the
// text, the line filling in violet as you read down it and the version being read lit. The line and markers are CSS,
// so they show without scripts; this only fills and lights them, and sets each release's date under its version
// ("0.1.0 - 2026-10-24" becomes "0.1.0", then "24 October 2026").
const prose = document.querySelector<HTMLElement>('.prose');
const versions = [...(prose?.querySelectorAll<HTMLElement>(':scope > h2') ?? [])];

if (prose && versions.length) {
  const fmt = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
  for (const h of versions) {
    const last = h.lastChild;
    const m = last?.nodeType === Node.TEXT_NODE ? /^\s*-\s*(\d{4}-\d{2}-\d{2})\s*$/.exec(last.textContent ?? '') : null;
    if (!m) continue;
    const time = document.createElement('time');
    time.className = 'tl-date';
    time.dateTime = m[1]!;
    time.textContent = fmt.format(new Date(`${m[1]}T00:00:00Z`));
    last!.replaceWith(time);
  }

  // Where a version's marker sits, in the text's own coordinates: on its first line, below the rule above it.
  const dot = (h: HTMLElement) => {
    const cs = getComputedStyle(h);
    const lh = parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.2;
    return h.offsetTop + parseFloat(cs.paddingTop) + lh / 2;
  };
  let dots: number[] = [];
  let current = -1;
  let atEnd = false;

  // The reading line is a third of the way down the window (as in toc.ts). The violet fill follows it down the line,
  // from the first marker to the last, and the last marker it has passed is lit.
  const update = () => {
    const y = window.innerHeight / 3 - prose.getBoundingClientRect().top;
    const first = dots[0]!;
    const last = dots[dots.length - 1]!;
    const at = atEnd ? last : Math.min(Math.max(y, first), last);
    let i = 0;
    dots.forEach((d, n) => {
      if (at >= d) i = n;
    });
    if (i !== current) {
      versions[current]?.classList.remove('tl-current');
      versions[i]?.classList.add('tl-current');
      current = i;
    }
    prose.style.setProperty('--tl-fill', `${at - first}px`);
  };
  const place = () => {
    dots = versions.map(dot);
    prose.style.setProperty('--tl-top', `${dots[0]}px`);
    update();
  };

  let raf = 0;
  window.addEventListener(
    'scroll',
    () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(update);
    },
    { passive: true },
  );
  // At the very bottom the line runs to the last version, since a short last one never reaches the reading line.
  const end = document.querySelector('footer');
  if (end) {
    new IntersectionObserver(
      ([e]) => {
        atEnd = !!e?.isIntersecting && document.documentElement.scrollHeight > window.innerHeight;
        update();
      },
      { threshold: 0.98 },
    ).observe(end);
  }
  new ResizeObserver(place).observe(prose);
  place();
}
