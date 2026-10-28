// The terminal types its commands as it comes into view; output lands a line at a time. The full text is in the page
// from the start (and for screen readers, always), so nothing depends on this running.
import { reduced } from './gsap';

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

document.querySelectorAll<HTMLElement>('[data-terminal]').forEach((term) => {
  if (reduced()) return;
  const lines = [...term.querySelectorAll<HTMLElement>('.line')];
  const texts = lines.map((l) => l.querySelector<HTMLElement>('.t')!.textContent ?? '');
  const cursor = term.querySelector<HTMLElement>('.cursor')!;

  const play = async () => {
    lines.forEach((l) => (l.hidden = true));
    for (const [i, line] of lines.entries()) {
      const t = line.querySelector<HTMLElement>('.t')!;
      const kind = line.dataset.kind;
      line.hidden = false;
      line.after(cursor);
      if (kind === 'cmd') {
        t.textContent = '';
        await wait(380);
        for (const ch of texts[i] ?? '') {
          t.textContent += ch;
          await wait(18 + Math.random() * 30);
        }
        await wait(260);
      } else if (kind === 'prompt') {
        t.textContent = texts[i] ?? '';
        await wait(900); // typing the password: getpass shows nothing
        // Argon2id stretches the password: 512 MB, 3 passes, about 280 ms on Apple silicon
        await wait(400);
      } else {
        await wait(kind === 'done' ? 260 : 140);
      }
    }
    lines[lines.length - 1]?.after(cursor);
  };

  const io = new IntersectionObserver(
    ([e]) => {
      if (e?.isIntersecting) {
        io.disconnect();
        void play();
      }
    },
    { threshold: 0.45 },
  );
  io.observe(term);
});
