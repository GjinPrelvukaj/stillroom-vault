// The licence signer's tests: npm test. Uses the test key pair in fixtures/, never the real one.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { signLicence, verifyLicence, type Licence } from './licence.ts';
import { editionFor, handleWebhook, paddleSigned, type Env, type KV } from './webhook.ts';

const fixture = JSON.parse(readFileSync(new URL('./fixtures/test-licence.json', import.meta.url), 'utf8')) as {
  publicKey: string;
  privateKey: string;
  licence: Licence;
  key: string;
};

// The Swift test (LicenseTests.nodeMintedKeyVerifies) checks this same key: neither side can drift alone.
test('the signer still mints exactly the fixture key', async () => {
  assert.equal(await signLicence(fixture.licence, fixture.privateKey), fixture.key);
  assert.deepEqual(await verifyLicence(fixture.key, fixture.publicKey), fixture.licence);
});

test('a changed payload no longer checks out', async () => {
  const [, payload = '', signature = ''] = fixture.key.split('.');
  const other = await signLicence({ ...fixture.licence, seats: 50 }, fixture.privateKey);
  assert.equal(await verifyLicence(`SR1.${other.split('.')[1]}.${signature}`, fixture.publicKey), null);
  assert.equal(await verifyLicence(`SR1.${payload}.${signature.replace(/^./, (c) => (c === 'A' ? 'B' : 'A'))}`, fixture.publicKey), null);
});

const secret = 'pdl_ntfset_test_secret';
const now = 1_790_000_000_000;
const sign = (body: string, ts = Math.floor(now / 1000), key = secret) =>
  `ts=${ts};h1=${createHmac('sha256', key).update(`${ts}:${body}`).digest('hex')}`;

test('Paddle signatures: good, bad, stale and malformed', async () => {
  const body = '{"event_id":"evt_1"}';
  assert.equal(await paddleSigned(sign(body), body, secret, now), true);
  assert.equal(await paddleSigned(sign(body, undefined, 'another secret'), body, secret, now), false);
  assert.equal(await paddleSigned(sign(body), body + ' ', secret, now), false);
  assert.equal(await paddleSigned(sign(body, now / 1000 - 301), body, secret, now), false, 'older than five minutes');
  assert.equal(await paddleSigned(sign(body, now / 1000 + 301), body, secret, now), false, 'from the future');
  assert.equal(await paddleSigned(sign(body, now / 1000 - 299), body, secret, now), true);
  assert.equal(await paddleSigned(null, body, secret, now), false);
  assert.equal(await paddleSigned('ts=;h1=', body, secret, now), false);
  assert.equal(await paddleSigned(sign(body), body, '', now), false);
  // While a secret is rotated, Paddle sends one h1 per secret.
  const both = `${sign(body, undefined, 'old secret')};h1=${sign(body).split('h1=')[1]}`;
  assert.equal(await paddleSigned(both, body, secret, now), true);
});

test('the edition comes from the price id', () => {
  const env = { PUBLIC_PADDLE_PRICE_PERSONAL: 'pri_personal', PUBLIC_PADDLE_PRICE_FAMILY: 'pri_family' };
  assert.deepEqual(editionFor('pri_personal', env), { edition: 'personal', seats: 1 });
  assert.deepEqual(editionFor('pri_family', env), { edition: 'family', seats: 5 });
  assert.equal(editionFor('pri_other', env), null);
  assert.equal(editionFor('', { PUBLIC_PADDLE_PRICE_PERSONAL: '' }), null, 'an unset price id matches nothing');
});

/** A signer with an in-memory KV, Paddle's customer API and an email provider that records what it was sent. */
function rig(options: { emailFails?: boolean } = {}) {
  const store = new Map<string, string>();
  const kv: KV = { get: async (k) => store.get(k) ?? null, put: async (k, v) => void store.set(k, v) };
  const sent: { to: string; text: string; html: string; reply_to: string; subject: string }[] = [];
  const env: Env = {
    PADDLE_WEBHOOK_SECRET: secret,
    PADDLE_API_KEY: 'pdl_test_apikey',
    PADDLE_ENV: 'sandbox',
    PUBLIC_PADDLE_PRICE_PERSONAL: 'pri_personal',
    PUBLIC_PADDLE_PRICE_FAMILY: 'pri_family',
    LICENCE_PRIVATE_KEY: fixture.privateKey,
    PADDLE_EVENTS: kv,
    EMAIL_PROVIDER: 'resend',
    EMAIL_API_KEY: 're_test',
    EMAIL_FROM: 'Stillroom Vault <licences@stillroomvault.com>',
  };
  const fetcher = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    if (url === 'https://sandbox-api.paddle.com/customers/ctm_1') {
      assert.equal((init?.headers as Record<string, string>).Authorization, 'Bearer pdl_test_apikey');
      return Response.json({ data: { name: 'Ana Buyer', email: 'ana@example.com' } });
    }
    if (url === 'https://api.resend.com/emails') {
      if (options.emailFails) return new Response('nope', { status: 503 });
      const mail = JSON.parse(String(init?.body));
      sent.push({ to: mail.to[0], text: mail.text, html: mail.html, reply_to: mail.reply_to, subject: mail.subject });
      return Response.json({ id: 'email_1' });
    }
    throw new Error(`unexpected fetch ${url}`);
  }) as typeof fetch;
  const post = (event: object, signature?: string) => {
    const body = JSON.stringify(event);
    return handleWebhook(
      new Request('https://stillroomvault.com/api/paddle-webhook', { method: 'POST', body, headers: { 'Paddle-Signature': signature ?? sign(body) } }),
      env,
      { fetch: fetcher, now: () => now },
    );
  };
  const keyIn = (text: string) => text.split('\n').find((line) => line.startsWith('SR1.')) ?? '';
  return { store, sent, post, keyIn };
}

const completed = (eventId: string, price = 'pri_family', quantity = 1) => ({
  event_id: eventId,
  event_type: 'transaction.completed',
  data: { id: 'txn_1', customer_id: 'ctm_1', billed_at: '2026-10-28T09:00:00Z', created_at: '2026-10-28T08:59:00Z', items: [{ quantity, price: { id: price } }] },
});

test('a completed purchase emails a key that checks out, for the edition bought', async () => {
  const r = rig();
  const response = await r.post(completed('evt_1'));
  assert.equal(response.status, 200);
  assert.equal(r.sent.length, 1);
  assert.equal(r.sent[0]?.to, 'ana@example.com');
  const licence = await verifyLicence(r.keyIn(r.sent[0]?.text ?? ''), fixture.publicKey);
  assert.deepEqual(licence, { v: 1, id: 'txn_1', edition: 'family', seats: 5, name: 'Ana Buyer', email: 'ana@example.com', issued: '2026-10-28' });
  const mail = r.sent[0]!;
  assert.equal(mail.reply_to, 'support@stillroomvault.com');
  assert.equal(mail.subject, 'Your Stillroom Vault licence');
  assert.ok(mail.html.includes(r.keyIn(mail.text)), 'the HTML carries the same key');
  assert.ok(mail.text.startsWith('Thank you, Ana.') && mail.text.includes('Issued: 28 October 2026') && mail.text.includes('Order: txn_1'));
});

test('a replayed event is refused: nothing is sent twice', async () => {
  const r = rig();
  await r.post(completed('evt_1'));
  const again = await r.post(completed('evt_1'));
  assert.equal(again.status, 200);
  assert.equal(await again.text(), 'already handled');
  assert.equal(r.sent.length, 1);
});

test('the same transaction always yields the same key', async () => {
  const r = rig();
  await r.post(completed('evt_1'));
  await r.post(completed('evt_2'));
  assert.equal(r.sent.length, 2);
  assert.equal(r.keyIn(r.sent[0]?.text ?? ''), r.keyIn(r.sent[1]?.text ?? ''));
});

test('a bad or stale signature is turned away before anything happens', async () => {
  const r = rig();
  const event = completed('evt_1');
  assert.equal((await r.post(event, sign(JSON.stringify(event), undefined, 'wrong'))).status, 401);
  assert.equal((await r.post(event, sign(JSON.stringify(event), now / 1000 - 600))).status, 401);
  assert.equal(r.sent.length, 0);
  assert.equal(r.store.size, 0);
});

test('other events and other products mint nothing', async () => {
  const r = rig();
  assert.equal((await r.post({ ...completed('evt_1'), event_type: 'transaction.created' })).status, 200);
  assert.equal((await r.post(completed('evt_2', 'pri_something_else'))).status, 200);
  assert.equal(r.sent.length, 0);
});

test('a failed email is not remembered, so Paddle retries and the retry sends the same key', async () => {
  const failing = rig({ emailFails: true });
  assert.equal((await failing.post(completed('evt_1'))).status, 500);
  assert.equal(failing.store.size, 0);
  const r = rig();
  await r.post(completed('evt_1'));
  assert.equal(r.keyIn(r.sent[0]?.text ?? '').length > 0, true);
});
