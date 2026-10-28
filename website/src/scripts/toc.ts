// Contents lists ([data-toc]): marks the link to the section being read with aria-current="location", which the CSS
// draws as a violet dot. Observers only, no scroll listener. Without scripts there's simply no dot.
// A section is "being read" once its heading crosses the top third of the window; at the very bottom of the page the
// last one wins, since a short last section never reaches that line. A page's chapter bar ([data-chapter]) names that
// section too, once the first one is reached.

document.querySelectorAll<HTMLElement>('[data-toc]').forEach((nav) => {
  const links = [...nav.querySelectorAll<HTMLAnchorElement>('a[href^="#"]')];
  const targets = links.map((a) => document.getElementById(decodeURIComponent(a.hash.slice(1))));
  if (!links.length || targets.some((t) => !t)) return;
  const sections = targets as HTMLElement[];

  const bar = document.querySelector<HTMLElement>('[data-chapter]');
  const barN = bar?.querySelector('[data-chapter-n]');
  const barText = bar?.querySelector('[data-chapter-text]');
  let current = -1;
  let atEnd = false;
  const mark = (i: number) => {
    if (i === current) return;
    links[current]?.removeAttribute('aria-current');
    links[i]?.setAttribute('aria-current', 'location');
    current = i;
    // The bar shows the chapter the marked heading belongs to (a numbered link at or above it).
    let c = i;
    while (c > 0 && !links[c]?.querySelector('.n')) c--;
    if (barN) barN.textContent = links[c]?.querySelector('.n')?.textContent ?? '';
    if (barText) barText.textContent = links[c]?.querySelector('.t')?.textContent ?? '';
  };
  const update = () => {
    const line = window.innerHeight / 3;
    if (bar) bar.hidden = sections[0]!.getBoundingClientRect().top > line;
    if (atEnd) return mark(sections.length - 1);
    let i = 0;
    sections.forEach((s, n) => {
      if (s.getBoundingClientRect().top <= line) i = n;
    });
    mark(i);
  };

  // The observed band is everything above the line a third of the way down, so a heading's state flips whenever it
  // crosses that line, even on a jump (Home, End, a link) that skips past it in one frame.
  const crossing = new IntersectionObserver(update, { rootMargin: '100000px 0px -67% 0px' });
  sections.forEach((s) => crossing.observe(s));

  // The end of the page: the footer coming fully into view.
  const end = document.querySelector('footer');
  if (end) {
    new IntersectionObserver(
      ([entry]) => {
        atEnd = !!entry?.isIntersecting && document.documentElement.scrollHeight > window.innerHeight;
        update();
      },
      { threshold: 0.98 },
    ).observe(end);
  }

  // A clicked link is marked at once, rather than after the jump.
  nav.addEventListener('click', (e) => {
    const i = links.indexOf((e.target as Element).closest('a') as HTMLAnchorElement);
    if (i >= 0) mark(i);
  });
});
