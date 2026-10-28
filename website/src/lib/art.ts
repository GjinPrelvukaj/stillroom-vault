// Art slots: an image is public/art/<name>.webp, and a slot without one falls back to a drawing (see ART.md).
import { existsSync } from 'node:fs';
import { join } from 'node:path';

export const hasArt = (name: string) => existsSync(join(process.cwd(), 'public', 'art', `${name}.webp`));

/** A page's own slot when its image exists, otherwise the slot it shares with its section (ART.md, "Per page"). */
export const ownArt = (name: string, shared: string) => (hasArt(name) ? name : shared);
