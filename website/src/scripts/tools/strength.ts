// The app's password check (macos/Sources/Stillroom/Security/PasswordStrength.swift), line for line, so the website
// says what the app would. Keep the two in step: same words, same rows, same costs, same 50-bit bar.

export const ENOUGH = 50;
/** The app also wants at least this many characters (LockView.shortest, KeySheets.shortest). */
export const SHORTEST = 12;

const lookalikes: Record<string, string> = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '@': 'a', '5': 's', $: 's', '7': 't', '!': 'i' };
const words = new Set([
  'password', 'passwort', 'qwerty', 'letmein', 'welcome', 'admin', 'login', 'iloveyou', 'love', 'monkey', 'dragon',
  'master', 'shadow', 'sunshine', 'princess', 'football', 'baseball', 'soccer', 'basketball', 'superman', 'batman',
  'trustno', 'hello', 'freedom', 'whatever', 'secret', 'vault', 'test', 'guest', 'summer', 'winter', 'spring',
  'autumn', 'michael', 'jordan', 'charlie', 'jessica', 'ashley', 'daniel', 'thomas', 'hunter', 'ranger', 'buster',
  'tigger', 'pepper', 'ginger', 'cookie', 'chocolate', 'flower', 'money', 'starwars', 'pokemon', 'minecraft',
  'computer', 'internet', 'apple', 'google', 'samsung', 'iphone', 'mother', 'father', 'family', 'friend', 'baby',
  'angel', 'lucky', 'happy', 'killer', 'blink', 'matrix', 'access', 'pass', 'word', 'user', 'root', 'changeme',
  'default', 'secure', 'private', 'mypassword', 'abc', 'qwertz', 'azerty', 'asdf', 'zxcv', 'kosovo', 'prishtina',
]);
const longestWordLength = Math.max(...[...words].map((w) => w.length));
const rows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm', '1234567890', 'qwertzuiop', 'yxcvbnm', 'azertyuiop'];

export type Part = { kind: 'word' | 'run' | 'year' | 'char'; text: string; bits: number };

/** The password in pieces, each with what it costs a guesser, in bits. */
export function parts(password: string): Part[] {
  const chars = Array.from(password);
  const plain = chars.map((c) => {
    const lower = c.toLowerCase();
    return lookalikes[lower] ?? lower;
  });
  const out: Part[] = [];
  let i = 0;
  while (i < chars.length) {
    const word = longestWord(plain, i);
    if (word) {
      const text = chars.slice(i, i + word);
      out.push({ kind: 'word', text: text.join(''), bits: 7 + (text.some((c) => isUpper(c)) ? 1 : 0) });
      i += word;
      continue;
    }
    const r = run(chars, i);
    if (r) {
      out.push({ kind: 'run', text: chars.slice(i, i + r).join(''), bits: 4 });
      i += r;
      continue;
    }
    const y = year(chars, i);
    if (y) {
      out.push({ kind: 'year', text: chars.slice(i, i + y).join(''), bits: 6 });
      i += y;
      continue;
    }
    out.push({ kind: 'char', text: chars[i]!, bits: Math.log2(pool(chars[i]!)) });
    i += 1;
  }
  return out;
}

export const bits = (password: string) => parts(password).reduce((sum, p) => sum + p.bits, 0);

function longestWord(plain: string[], i: number) {
  const longest = Math.min(longestWordLength, plain.length - i);
  for (let length = longest; length >= 3; length--) if (words.has(plain.slice(i, i + length).join(''))) return length;
  return 0;
}

/** Three or more of the same character, or in a row: abcd, 4321, qwerty, asdf. */
function run(chars: string[], i: number) {
  const lower = chars.map((c) => c.toLowerCase());
  let length = 1;
  while (i + length < lower.length && lower[i + length] === lower[i]) length++;
  if (length >= 3) return length;
  const ascii = (c: string) => (c.length === 1 && c.charCodeAt(0) < 128 ? c.charCodeAt(0) : null);
  for (const step of [1, -1]) {
    length = 1;
    while (i + length < lower.length) {
      const a = ascii(lower[i + length - 1]!);
      const b = ascii(lower[i + length]!);
      if (a === null || b === null || b - a !== step) break;
      length++;
    }
    if (length >= 3) return length;
  }
  for (const row of rows) {
    for (const line of [row, [...row].reverse().join('')]) {
      const start = line.indexOf(lower[i]!);
      if (start < 0) continue;
      length = 0;
      while (i + length < lower.length && start + length < line.length && lower[i + length] === line[start + length]) length++;
      if (length >= 3) return length;
    }
  }
  return 0;
}

/** A year from 1900 to 2099: birthdays and anniversaries. */
function year(chars: string[], i: number) {
  if (i + 4 > chars.length) return 0;
  const s = chars.slice(i, i + 4).join('');
  return /^\d{4}$/.test(s) && Number(s) >= 1900 && Number(s) <= 2099 ? 4 : 0;
}

const isUpper = (c: string) => /\p{Lu}/u.test(c);
function pool(c: string) {
  if (/\p{Ll}/u.test(c)) return 26;
  if (isUpper(c)) return 26;
  if (/\p{N}/u.test(c)) return 10;
  if (c.length === 1 && c.charCodeAt(0) < 128) return 33;
  return 100;
}

/** How long, on average (half the guesses), at so many guesses a second, in words. */
export function timeToGuess(b: number, perSecond: number) {
  const seconds = 2 ** (b - 1) / perSecond;
  const units: [number, string][] = [
    [60, 'second'],
    [60, 'minute'],
    [24, 'hour'],
    [365.25, 'day'],
  ];
  if (seconds < 1) return 'under a second';
  let n = seconds;
  for (const [size, name] of units) {
    if (n < size) return plural(n, name);
    n /= size;
  }
  if (n < 1000) return plural(n, 'year');
  if (n < 1e6) return `${Math.round(n / 1000).toLocaleString('en')} thousand years`;
  if (n < 1e9) return `${Math.round(n / 1e6).toLocaleString('en')} million years`;
  if (n < 1.38e10) return `${Math.round(n / 1e9).toLocaleString('en')} billion years`;
  return 'longer than the universe has existed';
}
const plural = (n: number, name: string) => {
  const r = Math.round(n);
  return `${r} ${name}${r === 1 ? '' : 's'}`;
};
