// The illustrations' live parts: a real two-factor code (RFC 6238, from the public demo key JBSWY3DPEHPK3PXP) and the
// lock screen's ring lighting a few random dots per key, as LockView does.
import { reduced } from './gsap';

/* ---------- Two-factor codes ---------- */
function base32(text: string): Uint8Array<ArrayBuffer> {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const ch of text.replace(/=+$/, '').toUpperCase()) {
    const i = alphabet.indexOf(ch);
    if (i < 0) continue;
    value = (value << 5) | i;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return new Uint8Array(out);
}

async function totp(key: CryptoKey, counter: number) {
  const msg = new ArrayBuffer(8);
  const view = new DataView(msg);
  view.setUint32(0, Math.floor(counter / 2 ** 32));
  view.setUint32(4, counter >>> 0);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, msg));
  const offset = mac[mac.length - 1]! & 0x0f;
  const bin =
    ((mac[offset]! & 0x7f) << 24) | ((mac[offset + 1]! & 0xff) << 16) | ((mac[offset + 2]! & 0xff) << 8) | (mac[offset + 3]! & 0xff);
  const code = String(bin % 1_000_000).padStart(6, '0');
  return `${code.slice(0, 3)} ${code.slice(3)}`;
}

async function twoFactor(root: HTMLElement) {
  if (!window.crypto?.subtle) return;
  const secret = root.dataset.totp ?? '';
  const key = await crypto.subtle.importKey('raw', base32(secret), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const codeEl = root.querySelector<HTMLElement>('[data-code]')!;
  const arc = root.querySelector<SVGCircleElement>('[data-arc]')!;
  const left = root.querySelector<SVGTextElement>('[data-left]')!;
  const row = codeEl.closest<HTMLElement>('.otp')!;
  let counter = -1;
  const tick = async () => {
    const now = Date.now() / 1000;
    const c = Math.floor(now / 30);
    const remaining = 30 - Math.floor(now % 30);
    if (c !== counter) {
      counter = c;
      codeEl.textContent = await totp(key, c);
    }
    left.textContent = String(remaining);
    arc.style.strokeDashoffset = String(30 - remaining);
    row.classList.toggle('soon', remaining <= 5);
  };
  await tick();
  setInterval(tick, 1000);
}

document.querySelectorAll<HTMLElement>('[data-totp]').forEach((el) => void twoFactor(el));

/* ---------- Lock screen ring ---------- */
function lockDemo(root: HTMLElement) {
  const dots = [...root.querySelectorAll<SVGCircleElement>('.dr-dot')];
  const typed = root.querySelector<HTMLElement>('[data-typed]')!;
  const lit = new Set<number>();
  const word = 'quiet harbour lantern';
  let running = false;
  let visible = false;

  const draw = (newest: number | null) => {
    dots.forEach((d, i) => {
      d.classList.toggle('on', lit.has(i));
      d.classList.toggle('edge', i === newest);
      d.setAttribute('r', i === newest ? '2.56' : '1.6');
    });
  };
  const light = (on: boolean) => {
    const n = 4 + Math.floor(Math.random() * 6);
    let newest: number | null = null;
    for (let k = 0; k < n; k++) {
      const pool = dots.map((_, i) => i).filter((i) => lit.has(i) !== on);
      if (!pool.length) break;
      const pick = pool[Math.floor(Math.random() * pool.length)]!;
      if (on) lit.add(pick);
      else lit.delete(pick);
      newest = on ? pick : null;
    }
    draw(newest);
  };
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

  const run = async () => {
    if (running) return;
    running = true;
    while (visible) {
      for (let i = 0; i < word.length && visible; i++) {
        typed.textContent += '•';
        light(true);
        await wait(110 + Math.random() * 90);
      }
      await wait(1400);
      while (typed.textContent && visible) {
        typed.textContent = typed.textContent.slice(1);
        light(false);
        await wait(45);
      }
      lit.clear();
      draw(null);
      await wait(900);
    }
    running = false;
  };

  new IntersectionObserver(([e]) => {
    visible = !!e?.isIntersecting;
    if (visible) void run();
  }).observe(root);
}

if (!reduced()) document.querySelectorAll<HTMLElement>('[data-lock-demo]').forEach(lockDemo);
