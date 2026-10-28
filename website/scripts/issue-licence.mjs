// Issues a licence key by hand: Teams orders, and lost keys. The private key comes from the environment, never a file
// in the repository.
//
// Usage:
//   LICENCE_PRIVATE_KEY=… node scripts/issue-licence.mjs --edition teams --seats 12 --name "Office Ltd" \
//     --email it@office.example [--id man_2026_001] [--issued 2026-10-28]
//
// A lost key: pass the original order's id (txn_…), its billing day as --issued, and the buyer's name and email as
// Paddle has them. The key that comes out is the same one the webhook sent (signatures are deterministic).
// With LICENCE_PUBLIC_KEY set too, the key is checked against it before it's printed.
import { parseArgs } from 'node:util';
import { signLicence, verifyLicence, editions } from '../server/licence.ts';

const { values: a } = parseArgs({
  options: {
    edition: { type: 'string' },
    seats: { type: 'string' },
    name: { type: 'string' },
    email: { type: 'string' },
    id: { type: 'string' },
    issued: { type: 'string' },
  },
});

const privateKey = process.env.LICENCE_PRIVATE_KEY;
const fail = (why) => {
  console.error(`${why}\nUsage: LICENCE_PRIVATE_KEY=… node scripts/issue-licence.mjs --edition personal|family|teams --seats N --name NAME --email EMAIL [--id ID] [--issued YYYY-MM-DD]`);
  process.exit(1);
};
if (!privateKey) fail('LICENCE_PRIVATE_KEY is not set.');
if (!editions.includes(a.edition)) fail('--edition must be personal, family or teams.');
if (!a.email || !a.name) fail('--name and --email are needed.');
const seats = Number(a.seats ?? { personal: 1, family: 5 }[a.edition]);
if (!Number.isInteger(seats) || seats < 1) fail('--seats must be a whole number, 1 or more.');

const issued = a.issued ?? new Date().toISOString().slice(0, 10);
const id = a.id ?? `man_${issued.replaceAll('-', '')}_${crypto.randomUUID().slice(0, 8)}`;
const licence = { v: 1, id, edition: a.edition, seats, name: a.name, email: a.email, issued };
const key = await signLicence(licence, privateKey);

if (process.env.LICENCE_PUBLIC_KEY && !(await verifyLicence(key, process.env.LICENCE_PUBLIC_KEY))) {
  fail('The key made does not check out against LICENCE_PUBLIC_KEY: the two keys are not a pair.');
}
console.log(key);
