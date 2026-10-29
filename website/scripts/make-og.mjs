// Draws the link previews with the installed Playwright, from the built site: public/og.png for the site (and the
// home page), and public/og/<path>.jpg for every other page. A page with a picture (its hero or main image) gets that
// picture full-bleed, with the wordmark and its heading over a soft fade; a page without one gets a paper card with
// its eyebrow and heading. Base.astro uses a page's own preview once it exists. Run after a build, then build again:
//   npm run build && node scripts/make-og.mjs && npm run build
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const at = (path) => fileURLToPath(new URL(path, import.meta.url));
const dist = at('../dist/');
const text = (html) => html.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
const art = (src) => (src && existsSync(at(`../public${src}`)) ? `data:image/webp;base64,${readFileSync(at(`../public${src}`)).toString('base64')}` : '');

const ring = Array.from({ length: 16 }, (_, i) => {
  const a = (i / 16) * 2 * Math.PI - Math.PI / 2;
  return `<circle cx="${(12 + 8.6 * Math.cos(a)).toFixed(2)}" cy="${(12 + 8.6 * Math.sin(a)).toFixed(2)}" r="1.45" fill="${i < 4 ? '#6043ca' : '#16151a'}"/>`;
}).join('');
const card = ({ eyebrow, title, picture }) => `<!doctype html><html><head><style>
  body{margin:0}.card{width:1200px;height:630px;background:#f7f6f2;color:#16151a;font-family:-apple-system,system-ui,sans-serif;overflow:hidden;display:grid;grid-template-columns:${picture ? '1fr 500px' : '1fr'};grid-template-rows:100%;gap:48px;padding:64px 72px;box-sizing:border-box}
  .text{display:flex;flex-direction:column;min-width:0}
  .mark{display:flex;align-items:center;font-weight:700;font-size:26px;letter-spacing:.14em}.mark svg{width:25px;height:25px;margin:0 3px}
  .eyebrow{margin-top:auto;color:#6043ca;font-size:26px}
  h1{margin:14px 0 0;font-family:ui-serif,'New York',Georgia,serif;font-weight:500;font-size:${title.length > 60 ? 50 : title.length > 36 ? 60 : 72}px;line-height:1.08;letter-spacing:-.01em}
  .site{margin-top:auto;padding-top:28px;color:rgb(22 21 26/.6);font-size:22px}
  .pic{display:flex;align-items:center;justify-content:center;min-height:0}.pic img{max-width:100%;max-height:100%}
</style></head><body><div class="card"><div class="text"><div class="mark">STILLR<svg viewBox="0 0 24 24">${ring}</svg>OM</div>
  <div class="eyebrow">${eyebrow}</div><h1>${title}</h1><div class="site">stillroomvault.com</div></div>
  ${picture ? `<div class="pic"><img src="${picture}"></div>` : ''}</div></body></html>`;

// The picture filling the whole preview, darkened at the foot so the heading reads, lighter at the top for the mark.
const bleed = ({ title, picture }) => `<!doctype html><html><head><style>
  body{margin:0}.card{position:relative;width:1200px;height:630px;overflow:hidden;font-family:-apple-system,system-ui,sans-serif;color:#fff;background:#16151a}
  .card>img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
  .shade{position:absolute;inset:0;background:linear-gradient(rgb(10 9 12/.45),rgb(10 9 12/0) 28%,rgb(10 9 12/0) 45%,rgb(10 9 12/.82))}
  .mark{position:absolute;top:56px;left:72px;display:flex;align-items:center;font-weight:700;font-size:26px;letter-spacing:.14em}.mark svg{width:25px;height:25px;margin:0 3px}
  h1{position:absolute;left:72px;right:72px;bottom:60px;margin:0;font-family:ui-serif,'New York',Georgia,serif;font-weight:500;font-size:${title.length > 60 ? 48 : title.length > 36 ? 58 : 68}px;line-height:1.08;letter-spacing:-.01em;text-shadow:0 2px 24px rgb(0 0 0/.35)}
</style></head><body><div class="card"><img src="${picture}"><div class="shade"></div>
  <div class="mark">STILLR<svg viewBox="0 0 24 24">${ring.replaceAll('#16151a', '#ffffff')}</svg>OM</div><h1>${title}</h1></div></body></html>`;

const pages = readdirSync(dist, { recursive: true })
  .filter((f) => f.endsWith('index.html'))
  .map((f) => f.replace(/index\.html$/, '').replace(/\/$/, ''));
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
const shoot = async (data, path, type) => {
  await page.setContent(data.picture ? bleed(data) : card(data));
  await page.evaluate(() => Promise.all([...document.images].map((i) => i.decode())));
  await page.screenshot({ path, type, ...(type === 'jpeg' && { quality: 86 }) });
};
// Pages that show no picture of their own still have their print (ART.md, "Per page"): their preview uses it.
const prints = {
  changelog: 'page-changelog', checkout: 'page-pricing', download: 'page-download', features: 'page-features',
  format: 'page-format', license: 'page-legal-license', pricing: 'page-pricing', privacy: 'page-legal-privacy',
  refunds: 'page-legal-refunds', 'security-policy': 'page-legal-security-policy', security: 'page-security',
  support: 'page-support', terms: 'page-legal-terms', tools: 'article-tools-passphrase-generator',
};
mkdirSync(at('../public/og'), { recursive: true });
await shoot({ eyebrow: 'Stillroom Vault', title: 'The encrypted vault for your Mac that never goes online.', picture: art('/art/home-plate.webp') }, at('../public/og.png'), 'png');
for (const p of pages.filter(Boolean)) {
  const html = readFileSync(`${dist}${p}/index.html`, 'utf8');
  const title = text(html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/)?.[1] ?? '');
  const eyebrow = text(html.match(/<p class="eyebrow[^"]*"[^>]*>([\s\S]*?)<\/p>/)?.[1] ?? 'Stillroom Vault');
  const m = html.match(/(?:hero-picture|cover|og-picture)[^>]*>\s*<img src="([^"]+)"|class="banner-art"[^>]*?src="([^"]+)"/);
  const picture = art(m?.[1] ?? m?.[2] ?? (prints[p] && `/art/${prints[p]}.webp`));
  await shoot({ eyebrow, title, picture }, at(`../public/og/${p.replaceAll('/', '-')}.jpg`), 'jpeg');
}
await browser.close();
console.log(`public/og.png and ${pages.length - 1} page previews written`);
