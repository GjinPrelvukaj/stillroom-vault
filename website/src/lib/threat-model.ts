// The threat model's two lists, read out of docs/SECURITY.md at build time so the site says exactly what the doc says.
import { repoFile } from './repo';

function listAfter(md: string, marker: string): string[] {
  const start = md.indexOf(marker);
  if (start < 0) throw new Error(`docs/SECURITY.md no longer has "${marker}"; update src/lib/threat-model.ts`);
  const items: string[] = [];
  for (const line of md.slice(start + marker.length).split('\n').slice(1)) {
    if (line.startsWith('- ')) items.push(line.slice(2).trim());
    else if (items.length && line.trim() === '') break;
    else if (items.length) break;
  }
  if (!items.length) throw new Error(`No list after "${marker}" in docs/SECURITY.md`);
  return items;
}

/** Turns the little markdown these lines use (`code`) into HTML. */
export function inline(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
}

/** The first sentences of the paragraph or bullet that starts with `start`, up to `sentences` of them. */
function sentencesFrom(md: string, start: string, sentences: number): string {
  const at = md.indexOf(start);
  if (at < 0) throw new Error(`docs/SECURITY.md no longer has "${start}"; update src/lib/threat-model.ts`);
  const line = md.slice(at, md.indexOf('\n', at));
  return (line.match(/[^.]+\./g) ?? [line]).slice(0, sentences).join('').trim();
}

const md = repoFile('docs/SECURITY.md');
export const protects = listAfter(md, '**It protects against:**');
export const doesNot = listAfter(md, '**It does not protect against:**');
/** Two more limits from the rules, shown beside the list so it isn't the only thing a reader sees. */
export const alsoTrue = [
  sentencesFrom(md, "**Rollback isn't prevented.**", 2),
  sentencesFrom(md, 'Changing the password, making a new recovery key', 2),
];
