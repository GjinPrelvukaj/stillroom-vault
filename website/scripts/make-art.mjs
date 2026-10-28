// Makes the site's art (public/art/<slot>.webp) with OpenAI's image API, from the prompts in ART.md.
// A dev tool only: the site never calls it and ships nothing from it. The key comes from the environment, never a file.
//   OPENAI_API_KEY=… node scripts/make-art.mjs            every slot without an image
//   OPENAI_API_KEY=… node scripts/make-art.mjs menu-1     just these, replacing what's there
// OPENAI_IMAGE_MODEL picks another model (default gpt-image-1).
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';

const key = process.env.OPENAI_API_KEY;
if (!key) throw new Error('Set OPENAI_API_KEY first.');
const model = process.env.OPENAI_IMAGE_MODEL ?? 'gpt-image-1';

const md = readFileSync(new URL('../ART.md', import.meta.url), 'utf8');
const style = md.match(/Add to every prompt: \*"([^"]+)"\*/s)[1].replace(/\s+/g, ' ');
const prompts = Object.fromEntries(
  [...md.matchAll(/^\*\*([a-z0-9-]+)\*\*: ([\s\S]+?)(?:\n\n|$)/gm)].map((m) => [m[1], m[2].replace(/\s+/g, ' ').trim()]),
);
const tall = (slot) => slot.startsWith('learn-') || slot.startsWith('side-');

const asked = process.argv.slice(2);
for (const slot of asked) if (!prompts[slot]) throw new Error(`No prompt for "${slot}" in ART.md.`);
const out = new URL('../public/art/', import.meta.url);
mkdirSync(out, { recursive: true });
const todo = asked.length ? asked : Object.keys(prompts).filter((s) => !existsSync(new URL(`${s}.webp`, out)));
if (!todo.length) console.log('Every slot already has an image. Name slots to remake them.');

for (const slot of todo) {
  process.stdout.write(`${slot}… `);
  const res = await fetch('https://api.openai.com/v1/images/generations', {
    method: 'POST',
    headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      model,
      prompt: /^(wash|side|pattern)-/.test(slot) ? prompts[slot] : `${prompts[slot]} ${style}`, // paper washes stand alone
      size: slot.startsWith('pattern-') ? '1024x1024' : tall(slot) ? '1024x1536' : '1536x1024',
      quality: 'high',
      output_format: 'webp',
      output_compression: 80,
    }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`${slot}: ${body.error?.message ?? res.status}`);
  writeFileSync(new URL(`${slot}.webp`, out), Buffer.from(body.data[0].b64_json, 'base64'));
  console.log('saved');
}
