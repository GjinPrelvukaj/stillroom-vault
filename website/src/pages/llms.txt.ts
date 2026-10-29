// /llms.txt: a plain-text map of the site for AI assistants and agents (llmstxt.org), built from the same sources as
// the pages, so it never says anything the site doesn't.
import type { APIRoute } from 'astro';
import { download, email, pricing, site } from '../config';
import { doesNot, protects } from '../lib/threat-model';

const strip = (s: string) => s.replace(/`/g, '').replace(/\*\*/g, '');

export const GET: APIRoute = () => {
  const body = `# Stillroom Vault

> ${site.tagline} Files, notes, passwords and two-factor codes, sealed with AES-256-GCM under keys only the owner holds, in one folder on their Mac. No server, no account, no sync. Made by ${site.owners.join(' and ')}; sold by ${site.seller} through Paddle.

- Requires: ${download.requires}.
- Price: Free for ${pricing.freeItems} items with every feature; Stillroom Vault $39 one-time (one person, all their Macs, all 1.x updates); Family $129 one-time (up to 5 people); Teams upon request (${email.hello}). Tiers never differ in protection.
- If the password, recovery key and emergency kit are all lost, nobody can open the vault, not even its maker.
- The decoy is protection against thieves and abusers, not police: it doesn't fool someone with one password and a copy of the folder.
- Argon2id makes each password guess slow (512 MB, 3 passes, 4 lanes); it doesn't make a weak password safe.

## It protects against
${protects.map((p) => `- ${strip(p)}`).join('\n')}

## It does not protect against
${doesNot.map((p) => `- ${strip(p)}`).join('\n')}

## Pages
- [Features](${site.url}/features/): everything the app does, grouped as in its README
- [Security](${site.url}/security/): the threat model and the eleven rules the design rests on
- [File format](${site.url}/format/): every file in a vault, byte by byte, and the MIT-licensed reader stillroom-open.py
- [Pricing](${site.url}/pricing/)
- [Download](${site.url}/download/)
- [Support and FAQ](${site.url}/support/): forgotten passwords, backups, moving Macs
- [Changelog](${site.url}/changelog/)
- [About](${site.url}/about/): why Stillroom exists, what its makers hold themselves to, and how it's paid for
- [Free tools](${site.url}/tools/): passphrase and PIN generators, a password strength checker, two-factor codes and QR reader, file checksums, a printable backup code sheet and a Shamir demo, all run in the browser
- [Report a security problem](${site.url}/security-policy/): ${email.security}

## Legal
- [Terms and EULA](${site.url}/terms/)
- [Refund policy](${site.url}/refunds/): 14 days, no questions
- [Privacy policy](${site.url}/privacy/): the app collects nothing; the site sets no cookies and counts visits with Cloudflare Web Analytics, which identifies no one
- [Source licence](${site.url}/license/): FSL-1.1-ALv2
- [Source code](${site.repo}): one public snapshot per release, on GitHub
`;
  return new Response(body, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};
