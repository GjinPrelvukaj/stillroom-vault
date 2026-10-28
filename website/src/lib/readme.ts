// README.md's "Features" section, read at build time: its groups ("**Keep anything**") and their bullets.
import { repoFile } from './repo';

const links: Record<string, string> = {
  'docs/FORMAT.md': '/format/',
  'docs/SECURITY.md': '/security/',
  'tools/stillroom-open.py': '/format/#open-without-us',
  'CHANGELOG.md': '/changelog/',
};

function inline(md: string): string {
  return md
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_m, text: string, href: string) =>
      /^https?:/.test(href)
        ? `<a href="${href}" target="_blank" rel="noopener noreferrer">${text}</a>`
        : `<a href="${links[href] ?? href}">${text}</a>`,
    )
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/((?:<kbd>[^<]+<\/kbd>)+)/g, '<span class="nowrap">$1</span>')
    .replace(/\b(SHA-256|AES-256-GCM)\b/g, '<span class="nowrap">$1</span>');
}

export interface FeatureGroup {
  title: string;
  slug: string;
  items: string[];
}

export function readmeFeatures(): FeatureGroup[] {
  const md = repoFile('README.md');
  const start = md.indexOf('\n## Features');
  if (start < 0) throw new Error('README.md has no "## Features" section; update src/lib/readme.ts');
  const end = md.indexOf('\n## ', start + 5);
  const section = md.slice(start, end < 0 ? undefined : end);
  const groups: FeatureGroup[] = [];
  for (const line of section.split('\n')) {
    const heading = /^\*\*(.+)\*\*\s*$/.exec(line.trim());
    if (heading) {
      const title = heading[1]!;
      groups.push({ title, slug: title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, ''), items: [] });
    } else if (line.startsWith('- ') && groups.length) {
      groups[groups.length - 1]!.items.push(inline(line.slice(2).trim()));
    }
  }
  if (groups.length < 3) throw new Error('README.md "Features" no longer has its groups; update src/lib/readme.ts');
  return groups;
}
