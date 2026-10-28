// Stillroom licence keys: `SR1.<payload>.<signature>`, both base64url without padding. The payload is compact JSON;
// the signature is Ed25519 over the bytes of `SR1.<payload>`. The app checks it offline against the public key built
// into it (macos/Sources/Stillroom/Security/License.swift); keep the two in step. WebCrypto only, so the same code
// runs in the Pages Function and in Node (scripts/issue-licence.mjs, the tests).

export type Edition = 'personal' | 'family' | 'teams';

export interface Licence {
  v: 1;
  /** The Paddle transaction id, or a hand-issued id ("man_…"). */
  id: string;
  edition: Edition;
  seats: number;
  name: string;
  email: string;
  /** The day it was issued, YYYY-MM-DD. */
  issued: string;
}

export const editions: readonly Edition[] = ['personal', 'family', 'teams'];

const toBinary = (bytes: Uint8Array) => Array.from(bytes, (b) => String.fromCharCode(b)).join('');
export const base64 = (bytes: Uint8Array) => btoa(toBinary(bytes));
export const base64url = (bytes: Uint8Array) => base64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
export const fromBase64 = (text: string) => Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));

/** The payload with its fields always in one order, so one licence always signs to one key. */
function canonical(l: Licence): Licence {
  if (l.v !== 1 || !editions.includes(l.edition) || !Number.isInteger(l.seats) || l.seats < 1 || !l.id || !/^\d{4}-\d{2}-\d{2}$/.test(l.issued)) {
    throw new Error('not a licence this signer makes');
  }
  return { v: 1, id: l.id, edition: l.edition, seats: l.seats, name: l.name, email: l.email, issued: l.issued };
}

/** `privateKey` is the PKCS#8 key, base64, as scripts/make-licence-keys.mjs writes it. */
export async function signLicence(licence: Licence, privateKey: string): Promise<string> {
  const key = await crypto.subtle.importKey('pkcs8', fromBase64(privateKey.trim()), { name: 'Ed25519' }, false, ['sign']);
  const signed = `SR1.${base64url(new TextEncoder().encode(JSON.stringify(canonical(licence))))}`;
  const signature = new Uint8Array(await crypto.subtle.sign({ name: 'Ed25519' }, key, new TextEncoder().encode(signed)));
  return `${signed}.${base64url(signature)}`;
}

/** The app's check, for the tests and the issue script's self-check. `publicKey` is the raw 32 bytes, base64. */
export async function verifyLicence(text: string, publicKey: string): Promise<Licence | null> {
  const parts = text.replace(/\s+/g, '').split('.');
  if (parts.length !== 3 || parts[0] !== 'SR1') return null;
  const [, payload = '', signature = ''] = parts;
  try {
    const key = await crypto.subtle.importKey('raw', fromBase64(publicKey), { name: 'Ed25519' }, false, ['verify']);
    const ok = await crypto.subtle.verify({ name: 'Ed25519' }, key, fromBase64(signature), new TextEncoder().encode(`SR1.${payload}`));
    return ok ? (JSON.parse(new TextDecoder().decode(fromBase64(payload))) as Licence) : null;
  } catch {
    return null;
  }
}
