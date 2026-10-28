// Kept apart from releases.ts, which reads files at build time, so the browser can use it too.

/** -1, 0 or 1, comparing "1.0.10" and "1.0.9" as numbers. */
export function compareVersions(a: string, b: string): number {
  const [x, y] = [a, b].map((v) => v.split('.').map(Number));
  for (let i = 0; i < 3; i++) if (x![i] !== y![i]) return (x![i] ?? 0) < (y![i] ?? 0) ? -1 : 1;
  return 0;
}
