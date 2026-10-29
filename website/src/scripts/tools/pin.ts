// Random PINs, with the ones people guess first left out on request.
import { below } from './random';

// The 20 most used 4-digit PINs (DataGenetics, from 3.4 million leaked PINs), and common 6-digit ones.
const common = new Set([
  '1234', '1111', '0000', '1212', '7777', '1004', '2000', '4444', '2222', '6969', '9999', '3333', '5555', '6666',
  '1122', '1313', '8888', '4321', '2001', '1010', '2580', '0852', '123456', '654321', '111111', '000000', '123123', '666666',
  '121212', '112233', '789456', '159753', '147258', '123321', '696969', '102030',
]);

/** True for PINs a guesser tries early: common ones, one digit over and over, runs, repeated pairs, years. */
export function guessable(pin: string): boolean {
  if (common.has(pin)) return true;
  if (/^(\d)\1+$/.test(pin)) return true;
  const d = Array.from(pin, Number);
  const steps = d.slice(1).map((x, i) => (x - d[i]! + 10) % 10);
  if (steps.every((s) => s === 1) || steps.every((s) => s === 9)) return true;
  if (/^(\d\d)\1+$/.test(pin) || /^(\d\d\d)\1+$/.test(pin)) return true;
  if (pin.length === 4 && Number(pin) >= 1900 && Number(pin) <= 2099) return true;
  // A date: DDMM or MMDD.
  if (pin.length === 4) {
    const [a, b] = [Number(pin.slice(0, 2)), Number(pin.slice(2))];
    if ((a >= 1 && a <= 31 && b >= 1 && b <= 12) || (a >= 1 && a <= 12 && b >= 1 && b <= 31)) return true;
  }
  return false;
}

export function pin(length: number, skipGuessable: boolean): string {
  for (;;) {
    const p = Array.from({ length }, () => below(10)).join('');
    if (!skipGuessable || !guessable(p)) return p;
  }
}
