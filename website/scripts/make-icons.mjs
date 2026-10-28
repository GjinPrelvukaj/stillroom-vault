// Draws the favicons with the installed Playwright. Run after changing site-icon.png or favicon.svg:
//   node scripts/make-icons.mjs
// Browser tabs get the wordmark's dot ring (public/favicon.svg). The home-screen and install sizes are the site's icon,
// scripts/site-icon.png: the ring and lock printed on paper, cut out as a rounded square. The Mac app's own icon
// (macos/Resources/AppIcon.png, public/app-icon-*.webp) is separate and never changed here.
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const at = (path) => new URL(path, import.meta.url);
const siteIcon = `data:image/png;base64,${readFileSync(at('site-icon.png')).toString('base64')}`;

const browser = await chromium.launch();
const page = await browser.newPage();
/** PNG bytes of `src` cropped to its opaque box and drawn at `size`; `flatten` fills transparency with the tile's edge. */
const draw = (src, size, { crop = false, flatten = false } = {}) =>
  page.evaluate(
    async ({ src, size, crop, flatten }) => {
      const img = new Image();
      img.src = src;
      await img.decode();
      const w = img.naturalWidth || size;
      const h = img.naturalHeight || size;
      let box = { x: 0, y: 0, w, h };
      const full = document.createElement('canvas');
      full.width = w;
      full.height = h;
      const fx = full.getContext('2d');
      fx.drawImage(img, 0, 0, w, h);
      if (crop) {
        const { data } = fx.getImageData(0, 0, w, h);
        let x0 = w, y0 = h, x1 = 0, y1 = 0;
        for (let y = 0; y < h; y++)
          for (let x = 0; x < w; x++)
            if (data[(y * w + x) * 4 + 3] > 8) {
              x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y);
            }
        const side = Math.max(x1 - x0, y1 - y0) + 1;
        box = { x: x0, y: y0, w: side, h: side };
      }
      const out = document.createElement('canvas');
      out.width = out.height = size;
      const ox = out.getContext('2d');
      ox.imageSmoothingQuality = 'high';
      if (flatten) {
        // The colour just inside the tile's left edge, halfway down, so the corners blend into the rim.
        const [r, g, b] = fx.getImageData(box.x + Math.round(box.w * 0.03), box.y + Math.round(box.h / 2), 1, 1).data;
        ox.fillStyle = `rgb(${r} ${g} ${b})`;
        ox.fillRect(0, 0, size, size);
      }
      ox.drawImage(full, box.x, box.y, box.w, box.h, 0, 0, size, size);
      return [...new Uint8Array(await (await new Promise((done) => out.toBlob(done, 'image/png'))).arrayBuffer())];
    },
    { src, size, crop, flatten },
  ).then((bytes) => Buffer.from(bytes));

/** An .ico holding PNG images, which every current browser reads. */
function ico(images) {
  const head = Buffer.alloc(6 + 16 * images.length);
  head.writeUInt16LE(1, 2);
  head.writeUInt16LE(images.length, 4);
  let offset = head.length;
  images.forEach(({ size, png }, i) => {
    const e = 6 + 16 * i;
    head.writeUInt8(size % 256, e);
    head.writeUInt8(size % 256, e + 1);
    head.writeUInt16LE(1, e + 4);
    head.writeUInt16LE(32, e + 6);
    head.writeUInt32LE(png.length, e + 8);
    head.writeUInt32LE(offset, e + 12);
    offset += png.length;
  });
  return Buffer.concat([head, ...images.map((i) => i.png)]);
}

const write = (name, bytes) => {
  writeFileSync(at(`../public/${name}`), bytes);
  console.log(`public/${name} written`);
};
// Tab sizes are the wordmark's dot ring (public/favicon.svg, drawn by hand); the large icons are the app icon as it is.
const ring = `data:image/svg+xml;base64,${readFileSync(at('../public/favicon.svg')).toString('base64')}`;
write('favicon.ico', ico([{ size: 16, png: await draw(ring, 16) }, { size: 32, png: await draw(ring, 32) }, { size: 48, png: await draw(ring, 48) }]));
write('apple-touch-icon.png', await draw(siteIcon, 180, { crop: true, flatten: true }));
write('icon-192.png', await draw(siteIcon, 192, { crop: true }));
write('icon-512.png', await draw(siteIcon, 512, { crop: true }));
await browser.close();
