// The free tools (src/content/pages/tools/), grouped as on their hub, each with the kind of tool it is. The hub's
// sections and every tool page's chips are read from here.

export const toolGroups = [
  { id: 'passwords', title: 'Passwords and PINs', lead: 'Make ones that are hard to guess, and see how a guesser sees yours.', slugs: ['passphrase-generator', 'password-strength', 'pin-generator'] },
  { id: 'two-factor', title: 'Two-factor codes', lead: 'Check, move and keep the keys behind your six-digit codes.', slugs: ['two-factor-codes', 'qr-code-reader', 'recovery-code-sheet'] },
  { id: 'files', title: 'Files and secrets', lead: 'Check a download is genuine, and split a secret between people.', slugs: ['file-checksum', 'shamir-split'] },
] as const;

export const toolKind: Record<string, string> = {
  'passphrase-generator': 'Generator',
  'password-strength': 'Checker',
  'pin-generator': 'Generator',
  'two-factor-codes': 'Code maker',
  'qr-code-reader': 'Reader',
  'recovery-code-sheet': 'Printable',
  'file-checksum': 'Checker',
  'shamir-split': 'Demo',
};
