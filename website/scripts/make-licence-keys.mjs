// Makes Stillroom's licence signing key pair. Run it once, by hand, for production; never commit what it writes.
// Usage: node scripts/make-licence-keys.mjs <file for the private key, outside the repository>
//
// Prints the public key for the app (License.publicKey in macos/Sources/Stillroom/Security/License.swift) and writes
// the private key (PKCS#8, base64) to the file you name, readable only by you. Then:
//   1. Keep the private key in your password manager and on one offline backup (a USB stick in a drawer). Lose it and
//      no new key can be issued that 1.x accepts; leak it and anyone can make keys.
//   2. Give it to the signer:  npx wrangler pages secret put LICENCE_PRIVATE_KEY --project-name <the Pages project> < <file>
//   3. Delete the file.
import { writeFile } from 'node:fs/promises';
import { resolve, relative, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { base64 } from '../server/licence.ts';

const out = process.argv[2];
if (!out) {
  console.error('Usage: node scripts/make-licence-keys.mjs <file for the private key, outside the repository>');
  process.exit(1);
}
const repo = resolve(fileURLToPath(new URL('../../', import.meta.url)));
const inside = relative(repo, resolve(out));
if (!inside.startsWith('..') && !isAbsolute(inside)) {
  console.error('Refusing to write a private key inside the repository. Name a file outside it.');
  process.exit(1);
}

const pair = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
const privateKey = base64(new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey)));
const publicKey = base64(new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey)));
await writeFile(out, `${privateKey}\n`, { mode: 0o600, flag: 'wx' });

console.log(`Public key (for License.publicKey in the app, and LICENCE_PUBLIC_KEY for issue-licence.mjs):\n\n  ${publicKey}\n`);
console.log(`Private key written to ${resolve(out)} (only you can read it).`);
console.log('Keep it in your password manager and one offline backup, put it in the signer with');
console.log(`  npx wrangler pages secret put LICENCE_PRIVATE_KEY --project-name <the Pages project> < ${out}`);
console.log('then delete the file.');
