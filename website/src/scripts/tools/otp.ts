// Two-factor codes (RFC 6238 TOTP over RFC 4226 HOTP), as the app makes them (macos/.../Crypto/OneTimeCode.swift),
// plus reading setup keys, otpauth links and Google Authenticator's export QR codes. Pure functions, no DOM.

export type Algorithm = 'SHA-1' | 'SHA-256' | 'SHA-512';
export interface Account {
  secret: Uint8Array<ArrayBuffer>;
  issuer: string;
  name: string;
  algorithm: Algorithm;
  digits: number;
  period: number;
  type: 'totp' | 'hotp';
  counter: number;
}

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/** A setup key in base32 (spaces, dashes and padding ignored), or null when it isn't one. */
export function fromBase32(text: string): Uint8Array<ArrayBuffer> | null {
  const clean = text.replace(/[\s-]+/g, '').replace(/=+$/, '').toUpperCase();
  if (!clean || /[^A-Z2-7]/.test(clean)) return null;
  const out: number[] = [];
  let bits = 0;
  let value = 0;
  for (const ch of clean) {
    value = (value << 5) | ALPHABET.indexOf(ch);
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return out.length ? new Uint8Array(out) : null;
}

export function toBase32(bytes: Uint8Array): string {
  let out = '';
  let bits = 0;
  let value = 0;
  for (const b of bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out += ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += ALPHABET[(value << (5 - bits)) & 31];
  return out;
}

/** The code for one counter value (HOTP). */
export async function hotp(secret: Uint8Array<ArrayBuffer>, counter: number, digits = 6, algorithm: Algorithm = 'SHA-1') {
  const key = await crypto.subtle.importKey('raw', secret, { name: 'HMAC', hash: algorithm }, false, ['sign']);
  const msg = new Uint8Array(8);
  new DataView(msg.buffer).setBigUint64(0, BigInt(counter));
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, msg));
  const at = mac[mac.length - 1]! & 0x0f;
  const n = ((mac[at]! & 0x7f) << 24) | (mac[at + 1]! << 16) | (mac[at + 2]! << 8) | mac[at + 3]!;
  return String(n % 10 ** digits).padStart(digits, '0');
}

/** The code for a moment (TOTP): seconds since 1970, in steps of the period. */
export const totp = (a: Account, seconds = Date.now() / 1000) => hotp(a.secret, Math.floor(seconds / a.period), a.digits, a.algorithm);

const algorithms: Record<string, Algorithm> = { SHA1: 'SHA-1', SHA256: 'SHA-256', SHA512: 'SHA-512' };

/** A setup key or an otpauth:// link, as an account. Throws with a plain reason when it's neither. */
export function parse(input: string): Account {
  const text = input.trim();
  if (/^otpauth:/i.test(text)) {
    const url = new URL(text);
    const type = url.host.toLowerCase();
    if (type !== 'totp' && type !== 'hotp') throw new Error('This link isn’t for time-based or counter-based codes.');
    const secret = fromBase32(url.searchParams.get('secret') ?? '');
    if (!secret) throw new Error('The link has no setup key, or the key isn’t valid base32.');
    const label = decodeURIComponent(url.pathname.replace(/^\//, ''));
    const [labelIssuer = '', labelName] = label.includes(':') ? label.split(/:(.*)/s, 2) : ['', label];
    const algorithm = algorithms[(url.searchParams.get('algorithm') ?? 'SHA1').toUpperCase()];
    if (!algorithm) throw new Error('The link asks for a hash this tool doesn’t know.');
    const digits = Number(url.searchParams.get('digits') ?? 6);
    const period = Number(url.searchParams.get('period') ?? 30);
    return {
      secret,
      issuer: url.searchParams.get('issuer') ?? labelIssuer.trim(),
      name: (labelName ?? '').trim(),
      algorithm,
      digits: digits >= 6 && digits <= 10 ? digits : 6,
      period: period > 0 && period <= 600 ? period : 30,
      type,
      counter: Number(url.searchParams.get('counter') ?? 0),
    };
  }
  const secret = fromBase32(text);
  if (!secret) throw new Error('That isn’t a setup key: they use only the letters A to Z and the digits 2 to 7.');
  return { secret, issuer: '', name: '', algorithm: 'SHA-1', digits: 6, period: 30, type: 'totp', counter: 0 };
}

/** The account as an otpauth:// link, to paste into another app. */
export function toLink(a: Account) {
  const label = encodeURIComponent(a.issuer ? `${a.issuer}:${a.name}` : a.name || 'Account');
  const q = new URLSearchParams({ secret: toBase32(a.secret) });
  if (a.issuer) q.set('issuer', a.issuer);
  if (a.algorithm !== 'SHA-1') q.set('algorithm', a.algorithm.replace('-', ''));
  if (a.digits !== 6) q.set('digits', String(a.digits));
  if (a.type === 'totp' && a.period !== 30) q.set('period', String(a.period));
  if (a.type === 'hotp') q.set('counter', String(a.counter));
  return `otpauth://${a.type}/${label}?${q}`;
}

/**
 * Google Authenticator's "Export accounts" QR code: otpauth-migration://offline?data=<base64 protobuf>.
 * MigrationPayload { repeated OtpParameters otp_parameters = 1; ... }, and
 * OtpParameters { bytes secret = 1; string name = 2; string issuer = 3; Algorithm algorithm = 4;
 *                 DigitCount digits = 5; OtpType type = 6; int64 counter = 7; }.
 */
export function parseMigration(link: string): Account[] {
  const data = new URL(link).searchParams.get('data');
  if (!data) throw new Error('This export link holds no accounts.');
  const bin = atob(data.replace(/-/g, '+').replace(/_/g, '/'));
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  const accounts: Account[] = [];
  for (const [field, value] of fields(bytes)) {
    if (field !== 1 || !(value instanceof Uint8Array)) continue;
    const a: Account = { secret: new Uint8Array(), issuer: '', name: '', algorithm: 'SHA-1', digits: 6, period: 30, type: 'totp', counter: 0 };
    for (const [f, v] of fields(value)) {
      if (f === 1 && v instanceof Uint8Array) a.secret = new Uint8Array(v);
      else if (f === 2 && v instanceof Uint8Array) a.name = new TextDecoder().decode(v);
      else if (f === 3 && v instanceof Uint8Array) a.issuer = new TextDecoder().decode(v);
      else if (f === 4 && typeof v === 'number') a.algorithm = (['SHA-1', 'SHA-1', 'SHA-256', 'SHA-512'] as const)[v] ?? 'SHA-1';
      else if (f === 5 && typeof v === 'number') a.digits = v === 2 ? 8 : 6;
      else if (f === 6 && typeof v === 'number') a.type = v === 1 ? 'hotp' : 'totp';
      else if (f === 7 && typeof v === 'number') a.counter = v;
    }
    // A label "Issuer:name" carries the issuer twice; show it once.
    if (a.issuer && a.name.startsWith(`${a.issuer}:`)) a.name = a.name.slice(a.issuer.length + 1);
    if (a.secret.length) accounts.push(a);
  }
  if (!accounts.length) throw new Error('This export link holds no accounts this tool can read.');
  return accounts;
}

/** The fields of a protobuf message: varints as numbers, length-delimited ones as bytes. */
function* fields(buf: Uint8Array): Generator<[number, number | Uint8Array]> {
  let i = 0;
  const varint = () => {
    let n = 0;
    let shift = 1;
    while (i < buf.length) {
      const b = buf[i++]!;
      n += (b & 0x7f) * shift;
      if (!(b & 0x80)) return n;
      shift *= 128;
    }
    throw new Error('This export link is cut short.');
  };
  while (i < buf.length) {
    const tag = varint();
    const field = Math.floor(tag / 8);
    const wire = tag & 7;
    if (wire === 0) yield [field, varint()];
    else if (wire === 2) {
      const len = varint();
      yield [field, buf.subarray(i, i + len)];
      i += len;
    } else if (wire === 5) i += 4;
    else if (wire === 1) i += 8;
    else throw new Error('This export link isn’t one this tool can read.');
  }
}
