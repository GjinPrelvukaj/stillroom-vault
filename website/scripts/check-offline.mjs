// The website's own offline check, run by `npm run build` (like macos/Scripts/check-offline.sh for the app).
// It fails the build if anything in dist/ names a host other than the ones below:
//   - stillroomvault.com, paddle.com and github.com (and their subdomains), allowed anywhere;
//   - any address that is a plain link's href in a page (the articles cite their sources, the repository's documents
//     link out): following a link is the reader's choice, and nothing is loaded from it;
//   - identifiers that are never fetched: XML/SVG namespaces (www.w3.org) and the schema.org vocabulary in
//     structured data.
import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { extname, join, relative } from 'node:path';

const dist = fileURLToPath(new URL('../dist/', import.meta.url));

const allowed = ['stillroomvault.com', 'paddle.com', 'github.com'];

/** Exact strings that look like addresses but are only text, each with its reason. */
const textOnly = [
  { file: /^_astro\/gsap\.[\w-]+\.js$/, url: 'https://gsap.com', why: 'the text of GSAP’s “target not found” console warning' },
];

const hostOk = (host, list) => list.some((h) => host === h || host.endsWith(`.${h}`));
const textTypes = new Set(['.html', '.css', '.js', '.mjs', '.json', '.xml', '.txt', '.webmanifest', '.md', '.py', '.svg', '']);

async function* walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) yield* walk(path);
    else yield path;
  }
}

const problems = [];
let files = 0;
let urls = 0;
const urlPattern = /(?:https?:)?\/\/([a-z0-9-]+(?:\.[a-z0-9-]+)+)(?::\d+)?[^\s"'<>)\\`]*/gi;

for await (const file of walk(dist)) {
  const name = relative(dist, file).split('\\').join('/'); // Windows paths use backslashes
  if (!textTypes.has(extname(file)) && !name.startsWith('_headers')) continue;
  const text = await readFile(file, 'utf8');
  files += 1;
  for (const m of text.matchAll(urlPattern)) {
    const [whole, rawHost] = m;
    const host = rawHost.toLowerCase();
    urls += 1;
    if (hostOk(host, allowed)) continue;
    if (textOnly.some((t) => t.file.test(name) && whole === t.url)) continue;
    // An xmlns="…" value (SVG, sitemaps) is a name, not an address.
    if (/xmlns(:[\w-]+)?=["']$/.test(text.slice(Math.max(0, m.index - 20), m.index))) continue;
    // XML and SVG namespaces are names, not addresses: nothing fetches them.
    if (host === 'www.w3.org' && /^(https?:)?\/\/www\.w3\.org\/(2000\/svg|1999\/xlink|1999\/xhtml|XML\/1998\/namespace|2000\/xmlns|1998\/Math\/MathML)/.test(whole)) continue;
    // schema.org inside structured data is a vocabulary, read by search engines, never loaded by the page.
    if (host === 'schema.org' && extname(file) === '.html') {
      const open = text.lastIndexOf('<script type="application/ld+json">', m.index);
      const close = text.lastIndexOf('</script>', m.index);
      if (open > close) continue;
    }
    // A plain link: the whole address is an <a> element's href (or that link's visible text).
    if (extname(file) === '.html') {
      const before = text.slice(Math.max(0, m.index - 300), m.index);
      const inHref = /<a\b[^>]*\bhref=["']$/.test(before) && /^["']/.test(text.slice(m.index + whole.length));
      const inLinkText = before.lastIndexOf('<a ') > before.lastIndexOf('</a>');
      if (inHref || inLinkText) continue;
    }
    problems.push(`${name}: ${whole}`);
  }
}

if (problems.length) {
  console.error(`check-offline: ${problems.length} URL(s) to hosts the site may not use:`);
  for (const p of [...new Set(problems)]) console.error(`  ${p}`);
  process.exit(1);
}
console.log(`check-offline: ${files} files, ${urls} URLs, every one to an allowed host`);
