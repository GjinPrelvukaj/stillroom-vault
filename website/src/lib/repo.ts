// Files from the rest of the repository, read at build time so the site never drifts from them.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/** The repository root: the site is built from website/ (Cloudflare Pages' root directory). */
export const repoRoot = resolve(process.cwd(), '..');

export function repoFile(path: string): string {
  return readFileSync(resolve(repoRoot, path), 'utf8');
}

export function sha256(path: string): string {
  return createHash('sha256').update(readFileSync(resolve(repoRoot, path))).digest('hex');
}

export function lineCount(path: string): number {
  return repoFile(path).split('\n').length - 1;
}
