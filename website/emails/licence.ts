// The licence email: what a buyer gets after paying, with their key and how to use it. One function returns the
// subject, a plain-text version and an HTML version (tables and inline styles, as mail apps need).
//
// Its two pictures (public/email/) load from stillroomvault.com and are the same file for everyone, so they can't
// tell who opened what; and the email reads whole with pictures blocked. No tracking pixel, no rewritten links.
// Preview it with: node scripts/preview-licence-email.mjs

export type Edition = 'personal' | 'family' | 'teams';

export interface LicenceEmailInput {
  /** The buyer's name as Paddle has it (may be empty). */
  name: string;
  edition: Edition;
  seats: number;
  /** The licence key, one line. */
  key: string;
  /** Paddle's transaction id, for the buyer's records and for support. */
  orderId: string;
  /** The day it was issued, e.g. "28 October 2026". */
  issued: string;
}

export const SITE = 'https://www.stillroomvault.com';
export const C = {
  paper: '#f7f6f2',
  raised: '#efede6',
  ink: '#16151a',
  ink2: '#4a4852',
  quiet: '#76737d',
  hairline: '#dedbd3',
  violet: '#6043ca',
};
export const SANS = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif";
export const SERIF = "ui-serif, 'New York', 'Iowan Old Style', Charter, Georgia, 'Times New Roman', serif";
export const MONO = "ui-monospace, 'SF Mono', Menlo, Consolas, 'Courier New', monospace";

export const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function editionLine({ edition, seats }: LicenceEmailInput): { name: string; people: string } {
  switch (edition) {
    case 'family':
      return { name: 'Stillroom Vault Family', people: `Up to ${seats} people, each on all of their own Macs` };
    case 'teams':
      return { name: 'Stillroom Vault for Teams', people: `${seats} ${seats === 1 ? 'person' : 'people'}, each on all of their own Macs` };
    default:
      return { name: 'Stillroom Vault', people: 'One person, on all of their own Macs' };
  }
}

function sharing({ edition, seats }: LicenceEmailInput): string | null {
  if (edition === 'personal') return null;
  const others = seats - 1;
  return `Share this same key with up to ${others} other ${others === 1 ? 'person' : 'people'}. Each pastes it into their own Stillroom. Every vault stays its owner's alone: the key opens no one's files, and no one can open anyone else's.`;
}

/** The page every Stillroom email sits in: the header picture, the content, and the footer with the wordmark. */
export function emailPage(subject: string, preheader: string, body: string, footnote: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>${esc(subject)}</title>
</head>
<body style="margin:0;padding:0;background:${C.paper};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:${C.paper}">${esc(preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${C.paper}">
<tr><td align="center" style="padding:32px 16px">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px">

<tr><td style="padding:0 0 24px">
<img src="${SITE}/email/licence-header.jpg" width="600" alt="An old cabinet of drawers, one open on a letter closed with a violet wax seal" style="display:block;width:100%;max-width:600px;height:auto;border:0;border-radius:16px;background:${C.raised}">
</td></tr>

${body}<tr><td style="padding:32px 8px 0">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-top:1px solid ${C.hairline}">
<tr><td style="padding:28px 0 0">
<img src="${SITE}/email/wordmark.png" width="152" alt="STILLROOM" style="display:block;width:152px;height:auto;border:0">
<p style="margin:14px 0 0;font-family:${SANS};font-size:14px;line-height:1.5;color:${C.ink2}">The encrypted vault for your Mac that never goes online.</p>
<p style="margin:14px 0 0;font-family:${SANS};font-size:13px;line-height:1.6;color:${C.quiet}">
<a href="${SITE}/" style="color:${C.violet};text-decoration:none">stillroomvault.com</a>
&nbsp;·&nbsp; <a href="${SITE}/support/" style="color:${C.violet};text-decoration:none">Support</a>
&nbsp;·&nbsp; <a href="${SITE}/refunds/" style="color:${C.violet};text-decoration:none">Refunds within 14 days</a>
</p>
<p style="margin:14px 0 0;font-family:${SANS};font-size:12px;line-height:1.6;color:${C.quiet}">${esc(footnote)}</p>
</td></tr>
</table>
</td></tr>

</table>
</td></tr>
</table>
</body>
</html>`;
}

export function licenceEmail(input: LicenceEmailInput): { subject: string; text: string; html: string } {
  const first = input.name.trim().split(/\s+/)[0] ?? '';
  const hello = first ? `Thank you, ${first}.` : 'Thank you.';
  const ed = editionLine(input);
  const share = sharing(input);
  const subject = 'Your Stillroom Vault licence';

  const text = [
    `${hello} Stillroom Vault is yours, with every 1.x update.`,
    '',
    'YOUR LICENCE KEY',
    input.key,
    '',
    'TO ADD IT',
    '1. Open Stillroom Vault on your Mac.',
    '2. Go to Settings, then Licence.',
    '3. Paste the key. The 25-item limit lifts at once.',
    ...(share ? ['', share] : []),
    '',
    `Edition: ${ed.name}`,
    `People: ${ed.people}`,
    `Order: ${input.orderId}`,
    `Issued: ${input.issued}`,
    '',
    'Keep this email. Stillroom checks the key on your Mac, offline: it never contacts us to check it. If you lose it, reply to this email and we will send the same key again.',
    '',
    'A licence never opens or recovers a vault. Only your password, recovery key or emergency kit can.',
    '',
    '--',
    'Stillroom Vault: the encrypted vault for your Mac that never goes online.',
    `${SITE}  ·  Support: ${SITE}/support/  ·  Refunds within 14 days: ${SITE}/refunds/`,
    'Sold by Gjin Prelvukaj through Paddle.com, our Merchant of Record. Your receipt comes from Paddle separately.',
  ].join('\n');

  const p = (inner: string, extra = '') =>
    `<p style="margin:0 0 16px;font-family:${SANS};font-size:16px;line-height:1.6;color:${C.ink2};${extra}">${inner}</p>`;
  const fact = (label: string, value: string, last = false) =>
    `<tr><td style="padding:10px 0;${last ? '' : `border-bottom:1px solid ${C.hairline};`}font-family:${SANS};font-size:14px;color:${C.quiet};width:96px;vertical-align:top">${label}</td>` +
    `<td style="padding:10px 0;${last ? '' : `border-bottom:1px solid ${C.hairline};`}font-family:${SANS};font-size:14px;color:${C.ink};vertical-align:top">${value}</td></tr>`;
  const step = (n: number, inner: string) =>
    `<tr><td style="padding:0 12px 10px 0;vertical-align:top;width:24px"><div style="width:24px;height:24px;border-radius:12px;background:${C.ink};color:${C.paper};font-family:${SANS};font-size:12px;font-weight:600;line-height:24px;text-align:center">${n}</div></td>` +
    `<td style="padding:2px 0 10px;font-family:${SANS};font-size:16px;line-height:1.5;color:${C.ink2}">${inner}</td></tr>`;

  const footnote = 'Sold by Gjin Prelvukaj through Paddle.com, our Merchant of Record. Your receipt comes from Paddle separately.';
  const html = emailPage(subject, 'Your key, and how to add it. Checked on your Mac, offline.', `<tr><td style="padding:0 8px">
<p style="margin:0 0 8px;font-family:${SANS};font-size:13px;letter-spacing:0.02em;color:${C.violet}">Your licence</p>
<h1 style="margin:0 0 16px;font-family:${SERIF};font-size:34px;line-height:1.15;font-weight:400;color:${C.ink}">Stillroom Vault is yours.</h1>
${p(
  input.edition === 'personal'
    ? `${esc(hello)} Your licence covers every 1.x update, on all of your own Macs.`
    : `${esc(hello)} Your licence covers up to ${input.seats} ${input.seats === 1 ? 'person' : 'people'}, each on all of their own Macs, with every 1.x update.`,
)}
</td></tr>

<tr><td style="padding:8px 8px 24px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${C.raised};border:1px solid ${C.hairline};border-radius:14px">
<tr><td style="padding:20px 22px">
<p style="margin:0 0 10px;font-family:${SANS};font-size:13px;color:${C.quiet}">Your licence key</p>
<p style="margin:0;font-family:${MONO};font-size:14px;line-height:1.55;color:${C.ink};word-break:break-all">${esc(input.key)}</p>
<p style="margin:12px 0 0;font-family:${SANS};font-size:13px;color:${C.quiet}">Copy the whole line, from the first letter to the last.</p>
</td></tr>
</table>
</td></tr>

<tr><td style="padding:0 8px 8px">
<h2 style="margin:0 0 14px;font-family:${SERIF};font-size:22px;font-weight:400;color:${C.ink}">To add it</h2>
<table role="presentation" cellpadding="0" cellspacing="0" border="0">
${step(1, 'Open Stillroom Vault on your Mac.')}
${step(2, 'Go to <strong style="color:' + C.ink + ';font-weight:600">Settings › Licence</strong>.')}
${step(3, 'Paste the key. The 25-item limit lifts at once.')}
</table>
${share ? p(esc(share), 'margin-top:8px') : ''}
</td></tr>

<tr><td style="padding:16px 8px 8px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-top:1px solid ${C.hairline}">
${fact('Edition', esc(ed.name))}
${fact('People', esc(ed.people))}
${fact('Order', `<span style="font-family:${MONO};font-size:13px">${esc(input.orderId)}</span>`)}
${fact('Issued', esc(input.issued), true)}
</table>
</td></tr>

<tr><td style="padding:24px 8px 8px">
${p('<strong style="color:' + C.ink + ';font-weight:600">Keep this email.</strong> Stillroom checks the key on your Mac, offline: it never contacts us to check it. If you lose it, reply to this email and we’ll send the same key again.')}
${p('A licence never opens or recovers a vault. Only your password, recovery key or emergency kit can.', `font-size:14px;color:${C.quiet}`)}
</td></tr>

`, footnote);

  return { subject, text, html };
}
