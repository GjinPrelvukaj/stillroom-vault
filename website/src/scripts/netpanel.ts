// The home page's live line: how many files this page has loaded from other sites, from the browser's own Resource
// Timing record. Nothing is sent anywhere; this only reads what the browser already knows. It rolls into place
// (micro.ts) and turns orange if it's ever above zero.
import { roll } from './micro';
const panel = document.querySelector<HTMLElement>('[data-netpanel]');

if (panel && 'PerformanceObserver' in window) {
  const count = panel.querySelector<HTMLElement>('[data-foreign]')!;
  let others = 0;
  const add = (entry: PerformanceEntry) => {
    if (new URL(entry.name, location.href).origin === location.origin) return;
    others += 1;
    roll(count, others);
    count.style.color = 'var(--orange)';
  };
  performance.getEntriesByType('resource').forEach(add);
  new PerformanceObserver((list) => list.getEntries().forEach(add)).observe({ type: 'resource' });
}
