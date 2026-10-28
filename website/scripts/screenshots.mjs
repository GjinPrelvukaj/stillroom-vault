// Screenshots of every page at 390, 768 and 1440 px, with the real headers (scripts/serve.mjs must be running), and a
// report of console errors and CSP violations. Uses the Playwright that's already installed (require('playwright')).
// Usage: node scripts/screenshots.mjs [out folder] [base url]
import { createRequire } from 'node:module';
import { mkdir } from 'node:fs/promises';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const out = process.argv[2] ?? 'screenshots-out';
const base = process.argv[3] ?? 'http://localhost:4321';
const only = process.env.PAGES?.split(',');
const pages = only ?? [
  '/', '/features/', '/security/', '/format/', '/pricing/', '/download/', '/support/', '/changelog/',
  '/security-policy/', '/terms/', '/refunds/', '/privacy/', '/license/', '/404/',
];
const widths = (process.env.WIDTHS ?? '390,768,1440').split(',').map(Number);
await mkdir(out, { recursive: true });
const browser = await chromium.launch();
const problems = [];
for (const width of widths) {
  // Reduced motion shows every section in its finished state, so a full-page capture is complete.
  const context = await browser.newContext({ viewport: { width, height: 900 }, deviceScaleFactor: width < 800 ? 2 : 1, reducedMotion: 'reduce' });
  const page = await context.newPage();
  page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') problems.push(`${width} ${page.url()} [${m.type()}] ${m.text()}`); });
  page.on('pageerror', (e) => problems.push(`${width} ${page.url()} [pageerror] ${e.message}`));
  for (const p of pages) {
    await page.goto(base + p, { waitUntil: 'networkidle' });
    await page.waitForTimeout(400);
    const name = (p === '/' ? 'home' : p.replace(/\//g, '')) + `-${width}.png`;
    await page.screenshot({ path: `${out}/${name}`, fullPage: true });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    if (overflow > 0) problems.push(`${width} ${p} horizontal overflow ${overflow}px`);
  }
  await context.close();
}
await browser.close();
console.log(problems.length ? problems.join('\n') : 'no console errors, CSP violations or overflow');
