// The menu's main links roll their letters on hover and focus (after Skiper UI's text roll navigation, 58): each
// letter slides up and out while its twin slides in from below, from the middle of the word outwards. This splits
// the words and sets each letter's delay; the motion is CSS (Header.astro). Screen readers get the word once, from a
// visually hidden copy; the rolling letters are hidden from them. Without this script the links stay plain words.
const STAGGER = 35; // ms between letters, from the middle out

document.querySelectorAll<HTMLAnchorElement>('[data-text-roll] a').forEach((link) => {
  const word = link.textContent?.trim() ?? '';
  if (!word) return;
  const letters = [...word];
  const middle = (letters.length - 1) / 2;
  const row = (under: boolean) => {
    const r = document.createElement('span');
    r.className = under ? 'text-roll-row under' : 'text-roll-row';
    letters.forEach((ch, i) => {
      const s = document.createElement('span');
      s.textContent = ch === ' ' ? ' ' : ch;
      s.style.transitionDelay = `${Math.round(STAGGER * Math.abs(i - middle))}ms`;
      r.append(s);
    });
    return r;
  };
  const roll = document.createElement('span');
  roll.className = 'text-roll';
  roll.setAttribute('aria-hidden', 'true');
  roll.append(row(false), row(true));
  const spoken = document.createElement('span');
  spoken.className = 'visually-hidden';
  spoken.textContent = word;
  link.replaceChildren(roll, spoken);
});
