// Emails every buyer that a new version is out (emails/update.ts), since the app never checks for updates itself.
// Buyers come from Paddle: every completed transaction for the Personal or Family price, one email per address.
//
// Usage, from website/ (the release must already be in CHANGELOG.md as "## [1.0.1] - YYYY-MM-DD"):
//   node scripts/send-update-email.mjs 1.0.1                      # dry run: counts buyers, writes a preview
//   node scripts/send-update-email.mjs 1.0.1 --only you@example.com --send   # one real email, to check it
//   node scripts/send-update-email.mjs 1.0.1 --send [--skip stop.txt]       # everyone (minus stop.txt's lines)
//
// Needs PADDLE_API_KEY (transaction and customer read), PUBLIC_PADDLE_PRICE_PERSONAL and _FAMILY, and for --send
// EMAIL_API_KEY, EMAIL_FROM and EMAIL_PROVIDER, the same values the website's signer has in Cloudflare.
// People who replied "stop" go one address per line in the --skip file; keep it outside the repository.
import { readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import { updateEmail } from '../emails/update.ts';
import { parseReleases } from '../src/lib/releases.ts';
import { sendEmail } from '../server/email.ts';

const { values: a, positionals } = parseArgs({
  allowPositionals: true,
  options: { send: { type: 'boolean' }, only: { type: 'string' }, skip: { type: 'string' } },
});
const fail = (why) => {
  console.error(`${why}\nUsage: node scripts/send-update-email.mjs <version> [--only EMAIL] [--skip FILE] [--send]`);
  process.exit(1);
};

const version = positionals[0];
if (!version) fail('Which version?');
const release = parseReleases(readFileSync(new URL('../../CHANGELOG.md', import.meta.url), 'utf8')).find((r) => r.version === version);
if (!release) fail(`CHANGELOG.md has no "## [${version}] - YYYY-MM-DD" release.`);
const mail = updateEmail(release);

const env = process.env;
const prices = [env.PUBLIC_PADDLE_PRICE_PERSONAL, env.PUBLIC_PADDLE_PRICE_FAMILY].filter(Boolean);
if (!a.only && (!env.PADDLE_API_KEY || prices.length < 2)) fail('Set PADDLE_API_KEY, PUBLIC_PADDLE_PRICE_PERSONAL and PUBLIC_PADDLE_PRICE_FAMILY.');
const api = env.PADDLE_ENV === 'sandbox' ? 'https://sandbox-api.paddle.com' : 'https://api.paddle.com';

/** Every buyer's email address, lower-cased, once each. */
async function buyers() {
  const found = new Set();
  let url = `${api}/transactions?status=completed&include=customer&per_page=200`;
  while (url) {
    const r = await fetch(url, { headers: { Authorization: `Bearer ${env.PADDLE_API_KEY}`, 'Paddle-Version': '1' } });
    if (!r.ok) throw new Error(`Paddle answered ${r.status} listing transactions`);
    const { data, meta } = await r.json();
    for (const t of data) {
      const bought = t.items?.some((i) => prices.includes(i.price?.id));
      if (bought && t.customer?.email) found.add(t.customer.email.trim().toLowerCase());
    }
    url = meta?.pagination?.has_more ? meta.pagination.next : null;
  }
  return found;
}

const skip = new Set(a.skip ? readFileSync(a.skip, 'utf8').split('\n').map((l) => l.trim().toLowerCase()).filter(Boolean) : []);
const everyone = a.only ? new Set([a.only.trim().toLowerCase()]) : await buyers();
const to = [...everyone].filter((e) => !skip.has(e));

const preview = join(tmpdir(), `stillroom-update-${version}.html`);
writeFileSync(preview, mail.html);
console.log(`"${mail.subject}"\n${to.length} recipient(s)${skip.size ? `, ${everyone.size - to.length} skipped` : ''}. Preview: ${preview}`);
if (!a.send) {
  console.log('Dry run: nothing sent. Add --send to send.');
  process.exit(0);
}

let sent = 0;
for (const address of to) {
  try {
    await sendEmail(env, { to: address, replyTo: 'support@stillroomvault.com', ...mail });
    sent++;
  } catch (error) {
    console.error(`not sent to ${address}: ${error.message}`);
  }
  // Under Resend's default of two requests a second.
  await new Promise((r) => setTimeout(r, 600));
}
console.log(`Sent ${sent} of ${to.length}.`);
