// A small static server for dist/ that sends the headers from public/_headers, so local checks see the real CSP.
// Usage: node scripts/serve.mjs [port]
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { gzipSync } from 'node:zlib';

const root = fileURLToPath(new URL('../dist/', import.meta.url));
const port = Number(process.argv[2] ?? 4321);
const types = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.xml': 'application/xml', '.png': 'image/png', '.webp': 'image/webp', '.ico': 'image/x-icon',
  '.svg': 'image/svg+xml', '.txt': 'text/plain; charset=utf-8', '.webmanifest': 'application/manifest+json',
  '.py': 'text/plain; charset=utf-8', '.md': 'text/plain; charset=utf-8',
};

/** Parses Cloudflare's _headers: a path pattern line, then indented "Name: value" lines. */
async function rules() {
  const text = await readFile(join(root, '_headers'), 'utf8').catch(() => '');
  const out = [];
  let current = null;
  for (const line of text.split('\n')) {
    if (!line.trim() || line.trim().startsWith('#')) continue;
    if (!/^\s/.test(line)) {
      current = { pattern: line.trim(), headers: {} };
      out.push(current);
    } else if (current) {
      const i = line.indexOf(':');
      current.headers[line.slice(0, i).trim()] = line.slice(i + 1).trim();
    }
  }
  return out;
}
const matches = (pattern, path) =>
  new RegExp('^' + pattern.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$').test(path);

const headerRules = await rules();
createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', 'http://localhost');
  const path = decodeURIComponent(url.pathname);
  let file = join(root, normalize(path));
  if (!file.startsWith(root)) file = join(root, '404.html');
  try {
    if ((await stat(file)).isDirectory()) file = join(file, 'index.html');
  } catch {
    file = join(root, '404.html');
    res.statusCode = 404;
  }
  try {
    const body = await readFile(file);
    for (const r of headerRules) if (matches(r.pattern, path)) for (const [k, v] of Object.entries(r.headers)) res.setHeader(k, v);
    res.removeHeader('Strict-Transport-Security');
    if (!res.hasHeader('Content-Type')) res.setHeader('Content-Type', types[extname(file)] ?? 'application/octet-stream');
    // Locally there's no TLS, so don't ask the browser to upgrade.
    const csp = res.getHeader('Content-Security-Policy');
    if (typeof csp === 'string') res.setHeader('Content-Security-Policy', csp.replace('; upgrade-insecure-requests', ''));
    // Compress text as Cloudflare does, so local Lighthouse runs measure what visitors get.
    const type = String(res.getHeader('Content-Type') ?? '');
    if (/text|javascript|json|xml|svg|manifest/.test(type) && /gzip/.test(String(req.headers['accept-encoding'] ?? ''))) {
      res.setHeader('Content-Encoding', 'gzip');
      res.end(gzipSync(body));
    } else res.end(body);
  } catch {
    res.statusCode = 404;
    res.end('Not found');
  }
}).listen(port, () => console.log(`serving dist/ on http://localhost:${port}`));
