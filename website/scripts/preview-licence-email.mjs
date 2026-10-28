// Writes the licence email as it would be sent, with made-up details, to look at in a browser or mail app.
// Usage: node scripts/preview-licence-email.mjs [personal|family|teams] [file]   (default: personal, to stdout path)
import { writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { licenceEmail } from '../emails/licence.ts';

const edition = process.argv[2] ?? 'personal';
const seats = { personal: 1, family: 5, teams: 12 }[edition] ?? 1;
const mail = licenceEmail({
  name: 'Ada Lovelace',
  edition,
  seats,
  key: 'SR1.eyJ2IjoxLCJpZCI6InR4bl8wMWg4ZXhhbXBsZSIsImVkaXRpb24iOiJwZXJzb25hbCIsInNlYXRzIjoxLCJuYW1lIjoiQWRhIExvdmVsYWNlIiwiZW1haWwiOiJhZGFAZXhhbXBsZS5jb20iLCJpc3N1ZWQiOiIyMDI2LTEwLTI4In0.dGhpcy1pcy1hbi1leGFtcGxlLXNpZ25hdHVyZS1ub3QtYS1yZWFsLW9uZS1hdC1hbGwtc28tZG9udC10cnk',
  orderId: 'txn_01h8example0000000000000',
  issued: '28 October 2026',
});
const out = process.argv[3] ?? join(tmpdir(), `stillroom-licence-${edition}.html`);
await writeFile(out, mail.html);
await writeFile(out.replace(/\.html$/, '.txt'), `Subject: ${mail.subject}\n\n${mail.text}\n`);
console.log(out);
