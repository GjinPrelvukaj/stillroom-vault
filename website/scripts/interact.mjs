// Drives the interactive parts with motion on and reports errors and CSP violations. Dev aid, not part of the build.
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const out = process.argv[2] ?? '.';
const base = process.argv[3] ?? 'http://localhost:4321';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const problems = [];
page.on('console', (m) => { if (['error', 'warning'].includes(m.type())) problems.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', (e) => problems.push(`[pageerror] ${e.message}`));
await page.addInitScript(() => {
  document.addEventListener('securitypolicyviolation', (e) => console.error(`CSP violation: ${e.violatedDirective} ${e.blockedURI}`));
});
await page.goto(base + '/', { waitUntil: 'networkidle' });
await page.waitForTimeout(2600);
await page.screenshot({ path: `${out}/live-hero-a.png` });
await page.waitForTimeout(900);
await page.screenshot({ path: `${out}/live-hero-b.png` });
// Tabs by keyboard
await page.locator('#tab-vault').focus();
await page.keyboard.press('ArrowRight');
await page.waitForTimeout(1500);
await page.locator('#panel-lock').scrollIntoViewIfNeeded();
await page.waitForTimeout(2000);
await page.screenshot({ path: `${out}/live-lock.png` });
await page.keyboard.press('ArrowRight');
await page.waitForTimeout(1200);
await page.screenshot({ path: `${out}/live-2fa.png` });
const code = await page.locator('[data-code]').first().textContent();
// Seal demo
await page.locator('#seal-it').scrollIntoViewIfNeeded();
await page.click('[data-seal-form] button[type=submit]');
await page.waitForTimeout(1400);
await page.click('[data-open]');
await page.waitForTimeout(300);
const opened = await page.locator('[data-status]').textContent();
await page.click('[data-tamper]');
await page.waitForTimeout(200);
await page.click('[data-open]');
await page.waitForTimeout(300);
const refused = await page.locator('[data-status]').textContent();
await page.locator('.demo').screenshot({ path: `${out}/live-seal.png` });
// The network panel, on the home page
await page.locator('[data-netpanel]').scrollIntoViewIfNeeded();
await page.waitForTimeout(500);
const foreign = await page.locator('[data-foreign]').textContent();
await page.locator('[data-netpanel]').screenshot({ path: `${out}/live-net.png` });
// Decoy
await page.goto(base + '/features/decoy-password/', { waitUntil: 'networkidle' });
await page.locator('[data-decoy]').scrollIntoViewIfNeeded();
await page.click('[data-pick="a"]');
await page.waitForTimeout(400);
const answer = await page.locator('[data-answer]').textContent();
await page.click('#lens-password');
await page.waitForTimeout(500);
await page.locator('[data-decoy]').screenshot({ path: `${out}/live-decoy.png` });
// The vault reader's terminal, on the format page
await page.goto(base + '/format/', { waitUntil: 'networkidle' });
await page.locator('[data-terminal]').scrollIntoViewIfNeeded();
await page.waitForTimeout(5000);
await page.locator('[data-terminal]').screenshot({ path: `${out}/live-terminal.png` });
// Argon ring mid-scroll, on the security page
await page.goto(base + '/security/', { waitUntil: 'networkidle' });
await page.locator('[data-argon]').first().scrollIntoViewIfNeeded();
await page.mouse.wheel(0, 200);
await page.waitForTimeout(800);
await page.screenshot({ path: `${out}/live-argon.png` });
console.log({ code, opened, refused, answer, foreignRequests: foreign });
console.log(problems.length ? problems.join('\n') : 'no errors or CSP violations');
await browser.close();
