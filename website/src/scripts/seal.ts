// "Seal it yourself": AES-256-GCM in the browser, the way Stillroom seals a one-piece item (docs/FORMAT.md):
// Padmé-padded plaintext, sealed with its own fresh key, bound to "Vault item 3" + a fresh 16-byte id, laid out as
// nonce (12) | ciphertext | tag (16). Nothing here makes a request, and the page's CSP allows none beyond this site.
import { reduced } from './gsap';

const root = document.querySelector<HTMLElement>('[data-seal-demo]');

const hex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join(' ');

/** Padmé, as in FORMAT.md: sizes give away at most about 12%. */
export function padme(n: number) {
  if (n <= 1) return n;
  const e = Math.floor(Math.log2(n));
  const s = Math.floor(Math.log2(e)) + 1;
  const mask = 2 ** (e - s) - 1;
  return (n + mask) & ~mask;
}

if (root && window.crypto?.subtle) {
  const form = root.querySelector<HTMLFormElement>('[data-seal-form]')!;
  const text = root.querySelector<HTMLTextAreaElement>('#seal-text')!;
  const openBtn = root.querySelector<HTMLButtonElement>('[data-open]')!;
  const tamperBtn = root.querySelector<HTMLButtonElement>('[data-tamper]')!;
  const status = root.querySelector<HTMLElement>('[data-status]')!;
  const mark = root.querySelector<SVGElement>('[data-mark]')!;
  const hold = root.querySelector<HTMLButtonElement>('[data-hold]')!;
  const state = (s: 'idle' | 'busy' | 'sealed' | 'ok' | 'bad') => (mark.dataset.state = s);
  const keyEl = root.querySelector<HTMLElement>('[data-key]')!;
  const bindEl = root.querySelector<HTMLElement>('[data-bind]')!;
  const nonceEl = root.querySelector<HTMLElement>('[data-nonce]')!;
  const ctEl = root.querySelector<HTMLElement>('[data-ct]')!;
  const tagEl = root.querySelector<HTMLElement>('[data-tag]')!;
  const empty = root.querySelector<HTMLElement>('[data-empty]')!;
  const sizes = root.querySelector<HTMLElement>('[data-sizes]')!;
  const calm = reduced();
  const encoder = new TextEncoder();
  const SHOWN = 384; // ciphertext bytes drawn; the rest are counted

  let sealed: Uint8Array<ArrayBuffer> | null = null;
  let key: CryptoKey | null = null;
  let aad: Uint8Array<ArrayBuffer> | null = null;
  let length = 0;
  let flipped = -1;
  let seals = 0;
  let lastText = '';

  const say = (html: string) => {
    status.innerHTML = html;
  };

  /** Bytes resolve out of random hex, left to right, like the rest of the site. */
  const typeOut = (el: HTMLElement, final: string, ms: number) =>
    new Promise<void>((done) => {
      if (calm) {
        el.textContent = final;
        return done();
      }
      const start = performance.now();
      const chars = '0123456789abcdef';
      const frame = (now: number) => {
        const p = Math.min(1, (now - start) / ms);
        const fixed = Math.floor(final.length * p);
        let out = final.slice(0, fixed);
        for (let i = fixed; i < final.length; i++) out += final[i] === ' ' ? ' ' : chars[(Math.random() * 16) | 0];
        el.textContent = out;
        if (p < 1) requestAnimationFrame(frame);
        else done();
      };
      requestAnimationFrame(frame);
    });

  const draw = async (animate: boolean) => {
    if (!sealed) return;
    empty.hidden = true;
    const nonce = sealed.slice(0, 12);
    const ct = sealed.slice(12, sealed.length - 16);
    const tag = sealed.slice(sealed.length - 16);
    const ctShown = hex(ct.slice(0, SHOWN)) + (ct.length > SHOWN ? ` … ${ct.length - SHOWN} more bytes` : '');
    if (animate) {
      await Promise.all([typeOut(nonceEl, hex(nonce), 450), typeOut(ctEl, ctShown, 900), typeOut(tagEl, hex(tag), 1100)]);
    } else {
      nonceEl.textContent = hex(nonce);
      ctEl.textContent = ctShown;
      tagEl.textContent = hex(tag);
    }
    // Mark the changed byte, if it's one we draw.
    if (flipped >= 0) {
      const region = flipped < 12 ? nonceEl : flipped >= sealed.length - 16 ? tagEl : ctEl;
      const index = flipped < 12 ? flipped : flipped >= sealed.length - 16 ? flipped - (sealed.length - 16) : flipped - 12;
      if (region !== ctEl || index < SHOWN) {
        const parts = (region.textContent ?? '').split(' ');
        region.textContent = '';
        parts.forEach((p, i) => {
          if (i === index) {
            const mark = document.createElement('mark');
            mark.className = 'flipped';
            mark.textContent = p;
            region.append(mark);
          } else region.append(p);
          if (i < parts.length - 1) region.append(' ');
        });
      }
    }
  };

  // Hold to seal: holding fills the button and seals when it's full (700 ms); a plain click still seals at once.
  let holdTimer = 0;
  let heldOut = false;
  const startHold = () => {
    if (holdTimer || calm) return;
    hold.classList.add('holding');
    holdTimer = window.setTimeout(() => {
      heldOut = true;
      form.requestSubmit();
    }, 700);
  };
  const endHold = () => {
    clearTimeout(holdTimer);
    holdTimer = 0;
    hold.classList.remove('holding');
  };
  hold.addEventListener('pointerdown', startHold);
  hold.addEventListener('pointerup', endHold);
  hold.addEventListener('pointerleave', endHold);
  hold.addEventListener('keydown', (e) => {
    if ((e.key === ' ' || e.key === 'Enter') && !e.repeat) startHold();
  });
  hold.addEventListener('keyup', endHold);
  // The click that follows a completed hold has already sealed.
  hold.addEventListener('click', (e) => {
    if (heldOut) {
      e.preventDefault();
      heldOut = false;
    }
  });

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    state('busy');
    const plain = encoder.encode(text.value);
    const padded = new Uint8Array(padme(plain.length));
    padded.set(plain);
    key = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, true, ['encrypt', 'decrypt']);
    const nonce = crypto.getRandomValues(new Uint8Array(12));
    const sealedAs = crypto.getRandomValues(new Uint8Array(16));
    const label = encoder.encode('Vault item 3');
    aad = new Uint8Array(label.length + 16);
    aad.set(label);
    aad.set(sealedAs, label.length);
    const out = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, additionalData: aad, tagLength: 128 }, key, padded));
    sealed = new Uint8Array(12 + out.length);
    sealed.set(nonce);
    sealed.set(out, 12);
    length = plain.length;
    flipped = -1;
    seals += 1;

    const raw = new Uint8Array(await crypto.subtle.exportKey('raw', key));
    keyEl.textContent = hex(raw);
    bindEl.textContent = `“Vault item 3” + ${hex(sealedAs)}`;
    sizes.textContent = `${plain.length} bytes of text, padded to ${padded.length} (Padmé), sealed into ${sealed.length} bytes: 12 + ${padded.length} + 16.`;
    openBtn.disabled = false;
    tamperBtn.disabled = false;
    const again = seals > 1 && text.value === lastText;
    lastText = text.value;
    say(
      again
        ? 'Sealed again. <strong>Same text, entirely different bytes</strong>: a new key and a new nonce every time.'
        : 'Sealed. Without the key and the binding, these bytes say nothing about what you typed, beyond its rough size.',
    );
    state('sealed');
    await draw(true);
  });

  openBtn.addEventListener('click', async () => {
    if (!sealed || !key || !aad) return;
    try {
      const plain = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: sealed.slice(0, 12), additionalData: aad, tagLength: 128 },
        key,
        sealed.slice(12),
      );
      const shown = new TextDecoder().decode(new Uint8Array(plain).slice(0, length));
      state('ok');
      say(`<span class="ok">Opened.</span> The tag checks out, so every byte is as it was sealed: “${escape(shown)}”`);
    } catch {
      state('bad');
      say(
        '<span class="bad">Refused.</span> The tag no longer matches, so nothing comes out, not even part of the text. Seal it again to start over.',
      );
    }
  });

  tamperBtn.addEventListener('click', async () => {
    if (!sealed) return;
    // Pick a byte we draw, so you can see which one changed.
    const drawable = Math.min(sealed.length - 28, SHOWN);
    const choices = 12 + drawable + 16;
    let pick = Math.floor(Math.random() * choices);
    if (pick >= 12 + drawable) pick = sealed.length - 16 + (pick - 12 - drawable);
    sealed[pick] = sealed[pick]! ^ (1 << Math.floor(Math.random() * 8));
    flipped = pick;
    const where = pick < 12 ? 'the nonce' : pick >= sealed.length - 16 ? 'the tag' : 'the ciphertext';
    state('sealed');
    say(`One bit of one byte in ${where} is changed (marked in orange). Now press <strong>Open it</strong>.`);
    await draw(false);
  });

  function escape(s: string) {
    return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] ?? c);
  }
}
