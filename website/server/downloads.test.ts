import assert from 'node:assert/strict';
import { test } from 'node:test';
import { count, countKey } from './downloads.ts';
import type { KV } from './webhook.ts';

const day = new Date('2026-11-03T12:00:00Z');
const get = (path: string, headers: Record<string, string> = {}, method = 'GET') =>
  new Request(`https://www.stillroomvault.com${path}`, { method, headers: { 'user-agent': 'Mozilla/5.0 Safari', ...headers } });

test('a download counts once per file per day, and nothing else does', async () => {
  assert.equal(countKey(get('/download/Stillroom-1.1.1.zip'), day), '2026-11-03 Stillroom-1.1.1.zip');
  assert.equal(countKey(get('/download/Stillroom-1.1.1.zip', { range: 'bytes=0-' }), day), '2026-11-03 Stillroom-1.1.1.zip');
  assert.equal(countKey(get('/download/Stillroom-1.1.1.zip', { range: 'bytes=5000-' }), day), null);
  assert.equal(countKey(get('/download/Stillroom-1.1.1.zip', {}, 'HEAD'), day), null);
  assert.equal(countKey(get('/download/Stillroom-1.1.1.zip', { 'user-agent': 'Googlebot/2.1' }), day), null);
  assert.equal(countKey(get('/download/Stillroom-1.1.1.zip', { 'user-agent': 'curl/8.7' }), day), null);
  assert.equal(countKey(get('/download/notes.txt'), day), null);

  const store = new Map<string, string>();
  const kv: KV = { get: async (k) => store.get(k) ?? null, put: async (k, v) => void store.set(k, v) };
  await count(kv, '2026-11-03 Stillroom-1.1.1.zip');
  await count(kv, '2026-11-03 Stillroom-1.1.1.zip');
  await count(kv, null);
  await count(undefined, 'x');
  assert.deepEqual([...store], [['2026-11-03 Stillroom-1.1.1.zip', '2']]);
});
