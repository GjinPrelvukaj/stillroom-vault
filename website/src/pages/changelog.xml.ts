// /changelog.xml: the releases as an RSS feed, so anyone can follow new versions without giving us an email address.
import type { APIRoute } from 'astro';
import { site } from '../config';
import { releases } from '../lib/releases';

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export const GET: APIRoute = () => {
  const items = releases().map((r) => {
    const link = `${site.url}/changelog/#${r.slug}`;
    const title = `Stillroom Vault ${r.version}${r.security ? ': a security fix' : ''}`;
    const body = [r.intro && `<p>${esc(r.intro)}</p>`, r.notes.length && `<ul>${r.notes.map((n) => `<li>${esc(n)}</li>`).join('')}</ul>`, `<p><a href="${site.url}/download/">Download ${r.version}</a></p>`]
      .filter(Boolean)
      .join('');
    return `    <item>
      <title>${esc(title)}</title>
      <link>${link}</link>
      <guid isPermaLink="false">stillroom-${r.version}</guid>
      <pubDate>${new Date(`${r.date}T12:00:00Z`).toUTCString()}</pubDate>
      <description>${esc(body)}</description>
    </item>`;
  });
  return new Response(
    `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Stillroom Vault releases</title>
    <link>${site.url}/changelog/</link>
    <description>New versions of Stillroom Vault, the encrypted vault for your Mac that never goes online. Updates are manual: each one is here and on the download page.</description>
    <language>en</language>
${items.join('\n')}
  </channel>
</rss>
`,
    { headers: { 'Content-Type': 'application/rss+xml; charset=utf-8' } },
  );
};
