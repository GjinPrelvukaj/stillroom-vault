// GSAP, bundled and served from this site (no CDN), with the plugins the pages use registered once.
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { ScrambleTextPlugin } from 'gsap/ScrambleTextPlugin';
import { SplitText } from 'gsap/SplitText';

gsap.registerPlugin(ScrollTrigger, ScrambleTextPlugin, SplitText);

/** True when the visitor asked for less motion: every effect then shows its finished, still state. */
export const reduced = (): boolean => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/**
 * The app's springs (SwiftUI response / damping fraction) as GSAP eases, so a script-driven motion feels the same as
 * a CSS one. Use with `duration: springs.x.duration`.
 */
function spring(response: number, damping: number) {
  const w = (2 * Math.PI) / response;
  const wd = w * Math.sqrt(1 - damping * damping);
  const x = (t: number) => 1 - Math.exp(-damping * w * t) * (Math.cos(wd * t) + ((damping * w) / wd) * Math.sin(wd * t));
  let settle = 0;
  for (let t = 0; t < 3; t += 0.001) if (Math.abs(1 - x(t)) > 0.002) settle = t;
  return { ease: (p: number) => (p >= 1 ? 1 : x(p * settle)), duration: settle };
}

export const springs = {
  hover: spring(0.22, 0.78),
  change: spring(0.32, 0.86),
  appear: spring(0.4, 0.86),
  /** A softer, slower one for big things travelling across the hero. */
  drift: spring(0.9, 0.82),
};

export const HEX = '0123456789abcdef';

export { gsap, ScrollTrigger, SplitText };
