// /search.json: everything the header's search (components/Search.astro, scripts/search.ts) can find, built from the
// same sources as the pages so it never lists anything the site doesn't have. Fetched from this site only, on the
// first open of the search.
import type { APIRoute, MarkdownHeading } from 'astro';
import { getCollection } from 'astro:content';
import { supportFaq } from '../lib/faq';
import { readmeFeatures } from '../lib/readme';
import { sections, type Section } from '../lib/sections';

/** One result: title, url, group, a line under it, and its headings as [text, #anchor] pairs. */
interface Entry {
  t: string;
  u: string;
  g: string;
  d: string;
  h?: [string, string][] | undefined;
}

const headingsOf = (e: { rendered?: { metadata?: Record<string, unknown> } | undefined }) =>
  ((e.rendered?.metadata?.['headings'] as MarkdownHeading[] | undefined) ?? []).filter((h) => h.depth <= 3).map((h): [string, string] => [h.text, h.slug]);

export const GET: APIRoute = async () => {
  const docs = Object.fromEntries((await getCollection('docs')).map((d) => [d.id, headingsOf(d)]));
  const pages = (await getCollection('pages')).sort((a, b) => a.data.order - b.data.order);

  const top: Entry[] = [
    { t: 'Home', u: '/', g: 'Pages', d: 'The encrypted vault for your Mac that never goes online.' },
    {
      t: 'Features',
      u: '/features/',
      g: 'Pages',
      d: 'Everything the app does, grouped as in its README.',
      h: readmeFeatures().map((f): [string, string] => [f.title, f.slug]),
    },
    { t: 'Security', u: '/security/', g: 'Pages', d: 'The threat model and the rules the design rests on.', h: docs['security'] },
    { t: 'File format', u: '/format/', g: 'Pages', d: 'Every file in a vault, byte by byte, and the reader stillroom-open.py.', h: docs['format'] },
    { t: 'Pricing', u: '/pricing/', g: 'Pages', d: 'Free for 25 items, $39 once, or $129 for a family.' },
    { t: 'Download', u: '/download/', g: 'Pages', d: 'For Macs with Apple silicon, on macOS 26 or later.' },
    { t: 'Support', u: '/support/', g: 'Pages', d: 'Forgotten passwords, backups, moving Macs, and how to reach us.' },
    { t: 'Changelog', u: '/changelog/', g: 'Pages', d: 'Every notable change, by version.', h: docs['changelog'] },
  ];
  const articles: Entry[] = pages.map((p) => ({
    t: p.data.name,
    u: `/${p.id}/`,
    g: sections[p.id.split('/')[0] as Section].name,
    d: p.data.description,
    h: headingsOf(p),
  }));
  const questions: Entry[] = supportFaq.flatMap((group) =>
    group.items.map((qa) => ({ t: qa.q, u: `/support/#${qa.id}`, g: 'Support', d: group.title })),
  );
  const legal: Entry[] = [
    { t: 'Terms and EULA', u: '/terms/', g: 'Legal', d: 'What a licence covers, and the limits of our liability.' },
    { t: 'Refund policy', u: '/refunds/', g: 'Legal', d: 'A full refund within 14 days, for any reason.' },
    { t: 'Privacy policy', u: '/privacy/', g: 'Legal', d: 'The app collects nothing. This site sets no cookies and counts visits without identifying anyone.' },
    { t: 'Source licence', u: '/license/', g: 'Legal', d: 'FSL-1.1-ALv2: read, audit and build it for your own use.', h: docs['license'] },
    { t: 'Report a security problem', u: '/security-policy/', g: 'Legal', d: 'What to include, response times and safe harbour.' },
  ];

  return new Response(JSON.stringify([...top, ...articles, ...questions, ...legal]), {
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
};
