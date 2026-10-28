// A heading whose words drift in from the right and close up as you scroll it into place (after Skiper UI's 31
// Text scroll animation, word by word here rather than letter by letter). Tied to the scroll, so it never plays
// on its own. Without scripts, and with reduced motion, the heading is plain text and never moves.
import { gsap, reduced, SplitText } from './gsap';

if (!reduced()) {
  document.querySelectorAll<HTMLElement>('[data-converge]').forEach((el) => {
    el.style.perspective = '600px';
    SplitText.create(el, {
      type: 'words',
      aria: 'auto',
      autoSplit: true,
      onSplit: (self) => {
        // The heading is set left, so the first word holds its place and each later one starts further out.
        return gsap.from(self.words, {
          x: (i: number) => i * 48,
          rotateX: 35,
          opacity: 0.12,
          ease: 'none',
          stagger: 0.06,
          scrollTrigger: { trigger: el, start: 'top 95%', end: 'top 55%', scrub: 0.5 },
        });
      },
    });
  });
}
