// The repository's own documents, rendered at build time so the site never drifts from them. Nothing is copied by
// hand: change docs/SECURITY.md and the security page changes with the next build.
import { defineCollection } from 'astro:content';
import { z } from 'astro/zod';
import { glob, type Loader } from 'astro/loaders';
import { readFile } from 'node:fs/promises';
import { posix, resolve } from 'node:path';

const repoRoot = resolve(process.cwd(), '..');
const repoUrl = 'https://github.com/GjinPrelvukaj/Stillroom/blob/main/';

/** Repository files this site shows, and the page each one becomes. */
export const docPages: Record<string, { id: string; page: string }> = {
  'docs/SECURITY.md': { id: 'security', page: '/security/' },
  'docs/FORMAT.md': { id: 'format', page: '/format/' },
  'CHANGELOG.md': { id: 'changelog', page: '/changelog/' },
  '.github/SECURITY.md': { id: 'security-policy', page: '/security-policy/' },
  'LICENSE.md': { id: 'license', page: '/license/' },
  // Files the site serves as they are.
  'tools/stillroom-open.py': { id: '', page: '/tools/stillroom-open.py' },
  'tools/LICENSE.md': { id: '', page: '/tools/LICENSE.md' },
};

/** Points a link in a repository document at this site's page for it, or at the file in the repository. */
function rewrite(href: string, from: string): string {
  if (/^([a-z]+:|#|\/\/)/i.test(href)) return href;
  const [path = '', hash] = href.split('#');
  const target = posix.normalize(posix.join(posix.dirname(from), path));
  const known = docPages[target];
  const base = known ? known.page : repoUrl + target;
  return hash ? `${base}#${hash}` : base;
}

function prepare(md: string, from: string): { title: string; body: string } {
  const lines = md.split('\n');
  const h1 = lines.findIndex((l) => l.startsWith('# '));
  const title = h1 >= 0 ? lines[h1]!.slice(2).trim() : from;
  if (h1 >= 0) lines.splice(h1, 1);
  const body = lines
    .join('\n')
    // [text](link) and ![alt](link)
    .replace(/\]\(([^)\s]+)\)/g, (_m, href: string) => `](${rewrite(href, from)})`)
    // [label]: link reference definitions
    .replace(/^\[([^\]]+)\]:\s+(\S+)/gm, (_m, label: string, href: string) => `[${label}]: ${rewrite(href, from)}`);
  return { title, body };
}

const repoDocs = (): Loader => ({
  name: 'repo-docs',
  load: async ({ store, renderMarkdown, watcher, generateDigest }) => {
    store.clear();
    for (const [file, { id }] of Object.entries(docPages)) {
      if (!id || !file.endsWith('.md')) continue;
      const path = resolve(repoRoot, file);
      const raw = await readFile(path, 'utf8');
      const { title, body } = prepare(raw, file);
      const rendered = await renderMarkdown(body);
      store.set({
        id,
        data: { title, source: file },
        body,
        digest: generateDigest(raw),
        rendered,
      });
      watcher?.add(path);
    }
  },
});

export const collections = {
  docs: defineCollection({
    loader: repoDocs(),
    schema: z.object({ title: z.string(), source: z.string() }),
  }),
  /** The site's own articles: src/content/pages/<section>/<slug>.md, served at /<section>/<slug>/. */
  pages: defineCollection({
    loader: glob({ pattern: '*/*.md', base: './src/content/pages' }),
    schema: z.object({
      /** The <title>, before " · Stillroom Vault": 60 characters at most, so search results show it whole. */
      title: z.string().max(60),
      /** The meta description: 155 characters at most. */
      description: z.string().min(70).max(155),
      h1: z.string(),
      lead: z.string(),
      /** The short name used in lists and breadcrumbs. */
      name: z.string(),
      /** The day the facts on the page were last checked, as "27 October 2026". */
      updated: z.string(),
      /** Order on its hub. */
      order: z.number().default(50),
      /** Other pages on this site, as paths ("/learn/argon2id/"). */
      related: z.array(z.string()).default([]),
      faq: z.array(z.object({ q: z.string(), a: z.string() })).default([]),
      /** Where the facts about other products came from. */
      sources: z.array(z.object({ label: z.string(), url: z.url() })).default([]),
    }),
  }),
};
