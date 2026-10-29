// Fair random numbers from the browser's cryptographic generator: no modulo bias, so every value is equally likely.

/** A whole number from 0 up to (not including) n, for n up to 2^32. */
export function below(n: number): number {
  const limit = Math.floor(0x1_0000_0000 / n) * n;
  const buf = new Uint32Array(1);
  for (;;) {
    crypto.getRandomValues(buf);
    if (buf[0]! < limit) return buf[0]! % n;
  }
}
