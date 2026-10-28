// The email buyers get when a new version is out (scripts/send-update-email.mjs sends it). The app never checks for
// updates, so this, the download page and the releases feed are how people hear. Same frame as the licence email.
import { C, SANS, SERIF, SITE, emailPage, esc } from './licence.ts';

export interface UpdateEmailInput {
  version: string;
  security: boolean;
  /** The release's opening paragraph from CHANGELOG.md, if any. */
  intro: string;
  notes: string[];
  /** The release's anchor on /changelog/. */
  slug: string;
}

const MAX_NOTES = 8;

export function updateEmail(r: UpdateEmailInput): { subject: string; text: string; html: string } {
  const subject = r.security
    ? `Stillroom Vault ${r.version}: a security update, please install it`
    : `Stillroom Vault ${r.version} is out`;
  const notes = r.notes.slice(0, MAX_NOTES);
  const more = r.notes.length - notes.length;
  const notesUrl = `${SITE}/changelog/#${r.slug}`;
  const why = r.security
    ? 'This version fixes a security problem. Please update soon.'
    : 'Stillroom never checks for updates itself, since it never goes online, so we tell you.';
  const steps = [
    'Download the new version.',
    'Quit Stillroom (⌘Q).',
    'Open the download and drag Stillroom into Applications, replacing the old copy.',
  ];
  const stop = 'You get this because you bought Stillroom Vault. Don’t want update emails? Reply “stop”.';

  const text = [
    `Stillroom Vault ${r.version} is out. ${why}`,
    ...(r.intro ? ['', r.intro] : []),
    ...(notes.length ? ['', 'WHAT CHANGED', ...notes.map((n) => `- ${n}`), ...(more > 0 ? [`- and ${more} more: ${notesUrl}`] : [])] : []),
    '',
    'TO UPDATE',
    ...steps.map((s, i) => `${i + 1}. ${s}`),
    'Your vault, licence and settings stay as they are.',
    '',
    `Download: ${SITE}/download/`,
    `Release notes: ${notesUrl}`,
    '',
    stop,
    '',
    '--',
    'Stillroom Vault: the encrypted vault for your Mac that never goes online.',
    `${SITE}  ·  Support: ${SITE}/support/`,
  ].join('\n');

  const p = (inner: string, extra = '') =>
    `<p style="margin:0 0 16px;font-family:${SANS};font-size:16px;line-height:1.6;color:${C.ink2};${extra}">${inner}</p>`;
  const li = (inner: string) => `<li style="margin:0 0 8px;font-family:${SANS};font-size:15px;line-height:1.5;color:${C.ink2}">${inner}</li>`;

  const body = `<tr><td style="padding:0 8px">
<p style="margin:0 0 8px;font-family:${SANS};font-size:13px;letter-spacing:0.02em;color:${r.security ? '#b4561a' : C.violet}">${r.security ? 'Security update' : 'New version'}</p>
<h1 style="margin:0 0 16px;font-family:${SERIF};font-size:34px;line-height:1.15;font-weight:400;color:${C.ink}">Stillroom Vault ${esc(r.version)} is out.</h1>
${p(esc(why))}
${r.intro ? p(esc(r.intro)) : ''}
</td></tr>

<tr><td style="padding:8px 8px 8px">
<table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td style="border-radius:999px;background:${C.ink}">
<a href="${SITE}/download/" style="display:inline-block;padding:14px 28px;font-family:${SANS};font-size:16px;font-weight:600;color:${C.paper};text-decoration:none">Download ${esc(r.version)}</a>
</td></tr></table>
</td></tr>

${
  notes.length
    ? `<tr><td style="padding:24px 8px 8px">
<h2 style="margin:0 0 14px;font-family:${SERIF};font-size:22px;font-weight:400;color:${C.ink}">What changed</h2>
<ul style="margin:0 0 8px;padding-left:20px">${notes.map((n) => li(esc(n))).join('')}</ul>
${p(`<a href="${notesUrl}" style="color:${C.violet};text-decoration:none">${more > 0 ? `And ${more} more in the release notes` : 'Release notes'}</a>`, 'font-size:14px')}
</td></tr>`
    : ''
}

<tr><td style="padding:16px 8px 8px">
<h2 style="margin:0 0 14px;font-family:${SERIF};font-size:22px;font-weight:400;color:${C.ink}">To update</h2>
<ol style="margin:0 0 12px;padding-left:20px">${steps.map((s) => li(esc(s))).join('')}</ol>
${p('Your vault, licence and settings stay as they are: they live apart from the app.', `font-size:14px;color:${C.quiet}`)}
</td></tr>

`;

  return { subject, text, html: emailPage(subject, why, body, stop) };
}
