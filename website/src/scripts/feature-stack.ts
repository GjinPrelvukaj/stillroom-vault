// The features page's card stack (after Skiper UI's StickyCard002). The stage pins under the header and each card
// slides up over the one before, which steps back and tilts a little. Only on screens tall and wide enough to hold a
// whole card, and never with reduced motion: there the cards stay a plain list, as they are without scripts.
import { gsap, ScrollTrigger } from './gsap';

const stage = document.querySelector<HTMLElement>('[data-stack-stage]');
const cards = gsap.utils.toArray<HTMLElement>('[data-stack] > .feature-card');

if (stage && cards.length > 1) {
  const mm = gsap.matchMedia();
  mm.add('(min-width: 901px) and (min-height: 720px) and (prefers-reduced-motion: no-preference)', () => {
    stage.classList.add('pinned');
    const headerH = () => document.querySelector<HTMLElement>('[data-header]')?.offsetHeight ?? 0;
    // The tallest card must fit on screen, or a pinned card would hide its own foot: then stay a list.
    if (stage.querySelector<HTMLElement>('[data-stack]')!.offsetHeight > window.innerHeight - headerH() - 32) {
      stage.classList.remove('pinned');
      return;
    }
    // One screen of scrolling per card change.
    const step = () => window.innerHeight * 0.9;

    gsap.set(cards.slice(1), { yPercent: 115 });
    const tl = gsap.timeline({
      defaults: { ease: 'none', duration: 1 },
      scrollTrigger: {
        trigger: stage,
        start: () => `top ${headerH()}px`,
        end: () => `+=${step() * (cards.length - 1)}`,
        pin: true,
        scrub: 0.5,
        invalidateOnRefresh: true,
      },
    });
    cards.slice(1).forEach((card, i) => {
      const back = cards[i]!;
      tl.to(back, { scale: 0.9, rotation: -2, opacity: 0.55 }, i).to(card, { yPercent: 0 }, i);
    });

    // A link to a card (the chips at the top, the URL's #hash, or Tab reaching a link inside one) scrolls to the
    // point where that card is on top, since the cards no longer sit in the page's flow.
    const scrollToCard = (i: number, smooth: boolean) => {
      const st = tl.scrollTrigger!;
      window.scrollTo({ top: st.start + step() * i + 2, behavior: smooth ? 'smooth' : 'auto' });
    };
    const indexOf = (id: string) => cards.findIndex((c) => c.id === id);
    const onClick = (e: MouseEvent) => {
      const a = (e.target as Element).closest<HTMLAnchorElement>('a[href^="#"]');
      const i = a ? indexOf(a.hash.slice(1)) : -1;
      if (i < 0) return;
      e.preventDefault();
      history.replaceState(null, '', a!.hash);
      scrollToCard(i, true);
    };
    const onFocus = (e: FocusEvent) => {
      const i = cards.findIndex((c) => c.contains(e.target as Node));
      if (i >= 0 && Math.round(tl.progress() * (cards.length - 1)) !== i) scrollToCard(i, false);
    };
    document.addEventListener('click', onClick);
    stage.addEventListener('focusin', onFocus);
    const hashed = indexOf(location.hash.slice(1));
    if (hashed > 0) requestAnimationFrame(() => scrollToCard(hashed, false));

    return () => {
      document.removeEventListener('click', onClick);
      stage.removeEventListener('focusin', onFocus);
      stage.classList.remove('pinned');
    };
  });
  // Pictures load lazily and can change the page's height above later triggers.
  window.addEventListener('load', () => ScrollTrigger.refresh());
}
