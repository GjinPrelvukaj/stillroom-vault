// /sitemap.xml, the address people and tools try first. The sitemap itself is written by @astrojs/sitemap as
// /sitemap-index.xml (+ /sitemap-0.xml); this is a sitemap index pointing at the same file, so both addresses work.
import type { APIRoute } from 'astro';
import { site } from '../config';

export const GET: APIRoute = () =>
  new Response(
    `<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <sitemap><loc>${site.url}/sitemap-0.xml</loc></sitemap>
</sitemapindex>
`,
    { headers: { 'Content-Type': 'application/xml; charset=utf-8' } },
  );
