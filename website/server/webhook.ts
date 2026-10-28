// Paddle's webhook → a signed Stillroom licence, emailed to the buyer. Served by functions/api/paddle-webhook.ts.
//
// - Only a request signed with the webhook secret (Paddle-Signature: ts=…;h1=…, HMAC-SHA256 over "ts:raw body") and
//   no more than five minutes old is read.
// - Each event id is remembered (KV) once handled, so a replayed or retried event does nothing a second time.
// - The licence is built only from the transaction (its id and billing day) and the customer, and Ed25519 signatures
//   are deterministic, so the same transaction always yields the same key: a resend never mints a second one.
// - Nothing about the buyer is stored, and nothing is logged but event ids and types.

import { licenceEmail } from '../emails/licence.ts';
import { sendEmail, type Email, type EmailEnv } from './email.ts';
import { signLicence, type Edition, type Licence } from './licence.ts';

export interface KV {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

export interface Env extends EmailEnv {
  PADDLE_WEBHOOK_SECRET: string;
  PADDLE_API_KEY: string;
  /** "sandbox" for Paddle's sandbox; anything else is live. */
  PADDLE_ENV?: string;
  PUBLIC_PADDLE_PRICE_PERSONAL?: string;
  PUBLIC_PADDLE_PRICE_FAMILY?: string;
  LICENCE_PRIVATE_KEY: string;
  PADDLE_EVENTS: KV;
}

export interface Deps {
  fetch: typeof fetch;
  /** Milliseconds, like Date.now. */
  now: () => number;
}

export const maxAgeSeconds = 5 * 60;
/** Longer than Paddle keeps retrying (three days live). */
const rememberSeconds = 7 * 24 * 60 * 60;

const hexBytes = (hex: string) => Uint8Array.from(hex.match(/../g) ?? [], (h) => parseInt(h, 16));

/** Whether `header` signs `body` with `secret`, at most five minutes either side of `now`. */
export async function paddleSigned(header: string | null, body: string, secret: string, now: number): Promise<boolean> {
  if (!header || !secret) return false;
  const fields = header.split(';').map((part) => part.split('=', 2) as [string, string?]);
  const ts = fields.find(([k]) => k === 'ts')?.[1] ?? '';
  // Several h1 while Paddle rotates the secret: any one will do.
  const signatures = fields.filter(([k, v]) => k === 'h1' && v && /^[0-9a-f]{64}$/i.test(v)).map(([, v]) => v as string);
  if (!/^\d{1,12}$/.test(ts) || signatures.length === 0) return false;
  if (Math.abs(now / 1000 - Number(ts)) > maxAgeSeconds) return false;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
  const signed = new TextEncoder().encode(`${ts}:${body}`);
  for (const h1 of signatures) {
    // verify compares in constant time.
    if (await crypto.subtle.verify('HMAC', key, hexBytes(h1), signed)) return true;
  }
  return false;
}

/** The edition a price id sells, and how many people one of it covers. Teams is issued by hand. */
export function editionFor(priceId: string, env: Pick<Env, 'PUBLIC_PADDLE_PRICE_PERSONAL' | 'PUBLIC_PADDLE_PRICE_FAMILY'>): { edition: Edition; seats: number } | null {
  if (!priceId) return null;
  if (priceId === env.PUBLIC_PADDLE_PRICE_PERSONAL) return { edition: 'personal', seats: 1 };
  if (priceId === env.PUBLIC_PADDLE_PRICE_FAMILY) return { edition: 'family', seats: 5 };
  return null;
}

interface Transaction {
  id: string;
  customer_id: string | null;
  billed_at?: string | null;
  created_at: string;
  items: { quantity?: number; price?: { id?: string } }[];
}

/** The licence a completed transaction buys, or null if it buys none. The buyer comes from Paddle's API. */
export async function licenceFor(txn: Transaction, env: Env, deps: Deps): Promise<Licence | null> {
  const bought = txn.items
    .map((item) => ({ sold: editionFor(item.price?.id ?? '', env), quantity: Math.max(1, item.quantity ?? 1) }))
    .find((item) => item.sold);
  if (!bought?.sold || !txn.customer_id) return null;
  const api = env.PADDLE_ENV === 'sandbox' ? 'https://sandbox-api.paddle.com' : 'https://api.paddle.com';
  const response = await deps.fetch(`${api}/customers/${encodeURIComponent(txn.customer_id)}`, {
    headers: { Authorization: `Bearer ${env.PADDLE_API_KEY}`, 'Paddle-Version': '1' },
  });
  if (!response.ok) throw new Error(`Paddle customer lookup answered ${response.status}`);
  const { data } = (await response.json()) as { data: { name?: string | null; email: string } };
  return {
    v: 1,
    id: txn.id,
    edition: bought.sold.edition,
    seats: bought.sold.seats * bought.quantity,
    name: data.name?.trim() || data.email,
    email: data.email,
    issued: (txn.billed_at ?? txn.created_at).slice(0, 10),
  };
}

const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
/** "2026-10-28" → "28 October 2026". */
export const longDate = (day: string) => {
  const [y, m, d] = day.split('-').map(Number);
  return `${d} ${months[(m ?? 1) - 1]} ${y}`;
};

export function licenceMail(licence: Licence, key: string): Email {
  const mail = licenceEmail({
    // The licence falls back to the email address for a name; the greeting doesn't.
    name: licence.name === licence.email ? '' : licence.name,
    edition: licence.edition,
    seats: licence.seats,
    key,
    orderId: licence.id,
    issued: longDate(licence.issued),
  });
  return { to: licence.email, replyTo: 'support@stillroomvault.com', ...mail };
}

const answer = (status: number, text: string) => new Response(text, { status, headers: { 'Content-Type': 'text/plain' } });

// Workers refuse fetch called as a method of another object ("Illegal invocation"), hence the arrow.
export async function handleWebhook(request: Request, env: Env, deps: Deps = { fetch: (input, init) => fetch(input, init), now: () => Date.now() }): Promise<Response> {
  if (request.method !== 'POST') return answer(405, 'POST only');
  const body = await request.text();
  if (!(await paddleSigned(request.headers.get('Paddle-Signature'), body, env.PADDLE_WEBHOOK_SECRET, deps.now()))) {
    return answer(401, 'bad or stale signature');
  }
  let event: { event_id?: string; event_type?: string; data?: Transaction };
  try {
    event = JSON.parse(body);
  } catch {
    return answer(400, 'not JSON');
  }
  const id = event.event_id;
  if (!id) return answer(400, 'no event id');
  const seen = `event:${id}`;
  if (await env.PADDLE_EVENTS.get(seen)) return answer(200, 'already handled');

  if (event.event_type === 'transaction.completed' && event.data) {
    try {
      const licence = await licenceFor(event.data, env, deps);
      if (licence) {
        const key = await signLicence(licence, env.LICENCE_PRIVATE_KEY);
        await sendEmail(env, licenceMail(licence, key), deps.fetch);
        console.log(`licence sent for ${id}`);
      }
    } catch (error) {
      // Nothing is remembered, so Paddle retries; the retry signs the same key. Our own messages name no buyer.
      console.log(`licence not sent for ${id}: ${error instanceof Error ? error.message : 'unknown error'}`);
      return answer(500, 'not handled, try again');
    }
  }
  await env.PADDLE_EVENTS.put(seen, '1', { expirationTtl: rememberSeconds });
  return answer(200, 'ok');
}
