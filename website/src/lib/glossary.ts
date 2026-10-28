// Plain-worded definitions for the format page's terms, shown as tooltips on their first use (scripts/terms.ts).
// Each must stay true to docs/FORMAT.md and docs/SECURITY.md. `match` finds the term in the rendered text.
export interface Term {
  id: string;
  match: RegExp;
  text: string;
}

export const glossary: Term[] = [
  {
    id: 'aes-gcm',
    match: /\bAES-256-GCM\b/,
    text: 'The cipher behind every seal: AES with a 256-bit key, in Galois/Counter Mode. It hides the bytes and adds a tag, so a sealed file that was changed refuses to open.',
  },
  {
    id: 'nonce',
    match: /\bnonce\b/,
    text: 'A number used once: 12 random bytes at the front of each seal. A fresh one every time means one key never seals two things the same way.',
  },
  {
    id: 'tag',
    match: /\btag\b/,
    text: 'A short check worked out with a key over the bytes. Without the key it can’t be forged, so a single changed byte is caught.',
  },
  {
    id: 'aad',
    match: /\bauthenticated data\b/,
    text: 'A few bytes naming what was sealed, such as “Vault list 3”. They aren’t stored or hidden, but opening needs them given again, so a sealed file moved into another’s place fails to open.',
  },
  {
    id: 'argon2id',
    match: /\bArgon2id\b/,
    text: 'The password stretcher (RFC 9106). For a new vault, turning a password into a key takes 512 MB of memory and 3 passes, so every guess is slow, even on graphics cards.',
  },
  {
    id: 'salt',
    match: /\bsalt\b/,
    text: '16 random bytes kept in each key file and mixed into the stretch, so the same password makes a different key in every vault and guesses can’t be worked out ahead of time.',
  },
  {
    id: 'hkdf',
    match: /\bHKDF(?:-SHA256)?/,
    text: 'A standard way (RFC 5869) to make a new key from an existing one for one named job, so no key is used for two things.',
  },
  {
    id: 'hmac',
    match: /\bHMAC(?:-SHA256)?/,
    text: 'A checksum made with a key. Only someone holding the key can make one or check it.',
  },
  {
    id: 'padme',
    match: /\bPadmé/,
    text: 'A padding rule: each item is rounded up to one of a sparse set of sizes before it’s sealed, so its sealed size gives away its real size only to within about 12%.',
  },
  {
    id: 'shamir',
    match: /\bShamir’?'?s secret sharing\b/,
    text: 'Splits the kit’s secret into pieces. Any agreed number of them rebuild it; fewer say nothing at all about it.',
  },
  {
    id: 'enclave',
    match: /\bSecure Enclave\b/,
    text: 'The Mac’s own security chip. A key made inside it can be used there but never read out, which is why, with Lock to this Mac on, the password opens the vault only on this Mac (the recovery key and kit still open it anywhere).',
  },
  {
    id: 'hpke',
    match: /\bHPKE\b/,
    text: 'Sealing to a public key (RFC 9180). Wrong tries are written to the intruder log while the vault is locked, and only an open vault’s private key reads them.',
  },
];
