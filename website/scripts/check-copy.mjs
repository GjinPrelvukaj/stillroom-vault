// The site's articles (src/content/pages) are written plainly: no em or en dashes. Fails the build otherwise.
// Usage: node scripts/check-copy.mjs
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

const root = new URL('../src/content/pages/', import.meta.url).pathname;
const problems = [];
for (const section of await readdir(root)) {
  for (const file of (await readdir(join(root, section))).filter((f) => f.endsWith('.md'))) {
    const lines = (await readFile(join(root, section, file), 'utf8')).split('\n');
    lines.forEach((line, i) => {
      if (/[–—]/.test(line)) problems.push(`${section}/${file}:${i + 1}: a dash (— or –); use a comma, colon, period or parentheses`);
    });
  }
}
console.log(problems.length ? problems.join('\n') : 'check-copy: no dashes in the articles');
if (problems.length) process.exit(1);
