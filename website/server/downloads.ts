// Counts downloads of the app: one number per zip per day in the DOWNLOADS KV namespace ("2026-11-03 Stillroom-1.1.1.zip"
// → "4"), nothing about who. Read them in the dashboard (Storage › KV › DOWNLOADS). The zip itself is served as before.
import type { KV } from './webhook.ts';

export interface DownloadsEnv {
  DOWNLOADS?: KV;
}

// Crawlers, link previews and command-line fetchers aren't people downloading the app.
const BOTS = /bot|crawl|spider|slurp|preview|facebookexternalhit|embedly|curl|wget|python|go-http|java\/|headless|monitor|uptime/i;

/** The KV key to bump for this request, or null when it shouldn't count. */
export function countKey(request: Request, now = new Date()): string | null {
  if (request.method !== 'GET') return null;
  const file = new URL(request.url).pathname.split('/').pop() ?? '';
  if (!/^Stillroom-\d{1,3}\.\d{1,3}\.\d{1,3}\.zip$/.test(file)) return null;
  if (BOTS.test(request.headers.get('user-agent') ?? '')) return null;
  // A resumed download asks for the rest of the file: the first request already counted.
  const range = request.headers.get('range');
  if (range && !/^bytes=0-/.test(range)) return null;
  return `${now.toISOString().slice(0, 10)} ${file}`;
}

// ponytail: read-then-write, so two downloads in the same instant can count as one; fine at this volume, a Durable
// Object or Analytics Engine if it ever matters.
export async function count(kv: KV | undefined, key: string | null): Promise<void> {
  if (!kv || !key) return;
  const now = Number((await kv.get(key)) ?? '0');
  await kv.put(key, String(now + 1));
}
