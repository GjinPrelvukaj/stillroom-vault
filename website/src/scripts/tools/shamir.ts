// Shamir secret sharing over GF(256) (the AES field, x^8 + x^4 + x^3 + x + 1), one polynomial per byte. A demo of
// the idea behind Stillroom's emergency kit, not its format: pieces read as "need-number-hex" and only this page
// joins them. Four bytes of SHA-256 ride along with the secret, so pieces that don't belong together are caught.

const EXP = new Uint8Array(512);
const LOG = new Uint8Array(256);
{
  let x = 1;
  for (let i = 0; i < 255; i++) {
    EXP[i] = x;
    LOG[x] = i;
    // Multiply by the generator 3: x * 2 (with reduction) xor x.
    x ^= (x << 1) ^ (x & 0x80 ? 0x11b : 0);
  }
  for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255]!;
}
const mul = (a: number, b: number) => (a && b ? EXP[LOG[a]! + LOG[b]!]! : 0);
const div = (a: number, b: number) => (a ? EXP[LOG[a]! + 255 - LOG[b]!]! : 0);

const hex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
const check = async (b: Uint8Array<ArrayBuffer>) => new Uint8Array(await crypto.subtle.digest('SHA-256', b)).slice(0, 4);

/** Split text into n pieces, any k of which give it back. */
export async function split(text: string, n: number, k: number): Promise<string[]> {
  if (!(k >= 2 && n >= k && n <= 255)) throw new Error('Need at least 2 pieces, and no more than you make.');
  const body = new TextEncoder().encode(text);
  const secret = new Uint8Array([...body, ...(await check(body))]);
  const pieces = Array.from({ length: n }, () => new Uint8Array(secret.length));
  const coeffs = new Uint8Array(k - 1);
  secret.forEach((byte, i) => {
    crypto.getRandomValues(coeffs);
    for (let x = 1; x <= n; x++) {
      // f(x) = byte + c1·x + c2·x² + …, by Horner's rule.
      let y = 0;
      for (let j = k - 2; j >= 0; j--) y = mul(y ^ coeffs[j]!, x);
      pieces[x - 1]![i] = y ^ byte;
    }
  });
  return pieces.map((p, i) => `${k}-${i + 1}-${hex(p)}`);
}

/** Join pieces (one per line, or separated by spaces) back into the text. Throws with a plain reason. */
export async function join(input: string): Promise<string> {
  const found = input.match(/\b\d+-\d+-[0-9a-f]+\b/gi) ?? [];
  const byX = new Map<number, { k: number; y: Uint8Array }>();
  for (const piece of found) {
    const [k, x, h = ''] = piece.split('-');
    if (h.length % 2) continue;
    byX.set(Number(x), { k: Number(k), y: Uint8Array.from(h.match(/../g)!, (b) => parseInt(b, 16)) });
  }
  if (!byX.size) throw new Error('No pieces found. Each looks like 3-1-a4c09e…');
  const need = Math.max(...[...byX.values()].map((p) => p.k));
  if (byX.size < need) throw new Error(`These pieces need ${need} to open, and there ${byX.size === 1 ? 'is 1' : `are ${byX.size}`}.`);
  const used = [...byX.entries()].slice(0, need);
  const length = used[0]![1].y.length;
  if (used.some(([, p]) => p.y.length !== length)) throw new Error('These pieces come from different splits.');
  const secret = new Uint8Array(length);
  for (let i = 0; i < length; i++) {
    // Lagrange interpolation at x = 0.
    let s = 0;
    for (const [xj, pj] of used) {
      let num = 1;
      let den = 1;
      for (const [xm] of used) {
        if (xm === xj) continue;
        num = mul(num, xm);
        den = mul(den, xm ^ xj);
      }
      s ^= mul(pj.y[i]!, div(num, den));
    }
    secret[i] = s;
  }
  const body = secret.slice(0, -4);
  const ok = hex(await check(body)) === hex(secret.slice(-4));
  if (!ok) throw new Error('These pieces don’t belong together, or one was copied wrong.');
  return new TextDecoder().decode(body);
}
