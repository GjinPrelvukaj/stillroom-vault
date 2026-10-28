// The released versions, read from CHANGELOG.md at build time: "## [1.0.1] - 2027-02-03" headings (Unreleased is
// skipped). A release with a "### Security" section is a security release. Used by the changelog's "you have X"
// note (/releases.json), the feed (/changelog.xml) and scripts/send-update-email.mjs.
import { repoFile } from './repo.ts';

export interface Release {
  version: string;
  date: string;
  security: boolean;
  /** The heading's anchor on /changelog/, as the markdown renderer makes it. */
  slug: string;
  /** The opening paragraph, if any. */
  intro: string;
  /** Every bullet, with markdown links and code marks taken out. */
  notes: string[];
}

const plain = (md: string) => md.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1').replace(/[`*]/g, '').trim();
// github-slugger's rule, which Astro's markdown uses for heading ids: lower case, drop punctuation, spaces to dashes.
const slugOf = (heading: string) => heading.toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, '').replace(/ /g, '-');

export function parseReleases(md: string): Release[] {
  return md
    .split(/\n(?=## )/)
    .map((section) => {
      const head = /^## (\[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2}))\s*$/m.exec(section);
      if (!head) return null;
      const lines = section.split('\n').slice(1);
      const intro = lines.slice(0, lines.findIndex((l) => l.startsWith('#') || l.startsWith('- ')) >>> 0).join(' ');
      return {
        version: head[2]!,
        date: head[3]!,
        security: /^### Security\b/m.test(section),
        slug: slugOf(head[1]!),
        intro: plain(intro),
        notes: lines.filter((l) => l.startsWith('- ')).map((l) => plain(l.slice(2))),
      };
    })
    .filter((r): r is Release => r !== null);
}

export const releases = (): Release[] => parseReleases(repoFile('CHANGELOG.md'));

export { compareVersions } from './versions.ts';
