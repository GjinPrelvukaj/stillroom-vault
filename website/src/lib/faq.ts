// Questions and answers: one source for the pages and their FAQPage structured data. Answers are small HTML.
import { email } from '../config';

export interface QA {
  id: string;
  q: string;
  a: string;
}

export const homeFaq: QA[] = [
  {
    id: 'forgot',
    q: 'What if I forget my password?',
    a: `Use your recovery key, which you write down when you make the vault, or enough pieces of your emergency kit. If you’ve lost all three, nobody can open it, not even us. There’s no master key and no back door, ever. <a href="/support/#forgot">What to do, step by step</a>.`,
  },
  {
    id: 'see',
    q: 'Can you see my files?',
    a: 'No. Stillroom has no server and no account, and the app makes no network connections. Your files are sealed on your Mac with AES-256-GCM, under keys only you hold.',
  },
  {
    id: 'free',
    q: 'What happens at 25 items on the free version?',
    a: 'Adding more stops until you buy a licence. Opening, editing, exporting and backing up always keep working, licensed or not: Stillroom never holds your files hostage.',
  },
  {
    id: 'once',
    q: 'Is $39 a subscription?',
    a: 'No. It’s one payment, for every 1.x update. If there’s a 2.0, upgrading will cost $39 for 1.x owners, and 1.x keeps working forever. Every tier, Free included, has the same protection.',
  },
  {
    id: 'sync',
    q: 'Does it sync with my iPhone or my other Macs?',
    a: 'No. Your vault is one folder on your Mac, and you move it with a backup. Optional sync through a folder you choose, carrying only sealed files, is planned for 2.0.',
  },
  {
    id: 'gone',
    q: 'What if Stillroom stops being made?',
    a: 'The file format is public, and <a href="/format/#open-without-us"><code>stillroom-open.py</code></a>, which anyone may use (MIT), takes everything out with your password, recovery key or kit. You can also export everything as plain files at any time.',
  },
  {
    id: 'decoy',
    q: 'Will the decoy fool a forensic examiner?',
    a: 'Don’t count on it. It fools someone at the keyboard or with a copy of the folder, not someone who has one password and a copy: they can see the other vault holds something, though not what. It’s protection against thieves and abusers, not police. <a href="/security/#rules">Rule 2</a> says exactly what it does and doesn’t do.',
  },
  {
    id: 'audit',
    q: 'Has it been independently audited?',
    a: 'Not yet. An independent security review by someone named is planned, and its report will be published here in full, findings and fixes included. Until then, the <a href="/security/">security rules</a> and the <a href="/format/">file format</a> are public, so anyone can check our work.',
  },
  {
    id: 'macs',
    q: 'Which Macs does it run on?',
    a: 'Macs with Apple silicon (M1 or later) running macOS 26 or later. Intel Macs aren’t supported. A Windows version is in progress, with no date yet.',
  },
  {
    id: 'offline',
    q: 'Does it need an internet connection?',
    a: 'No. Stillroom makes no network connections at all, and every build is checked for networking code and refused if it has any. Updates are downloads from this site, when you choose.',
  },
];

export const supportFaq: { title: string; id: string; items: QA[] }[] = [
  {
    title: 'Forgot your password?',
    id: 'forgot',
    items: [
      {
        id: 'forgot-recovery',
        q: 'Use your recovery key',
        a: 'On the lock screen, choose <strong>Use Recovery Key</strong> and type the key you wrote down when you made the vault (25 characters in five groups). You’ll set a new password next.',
      },
      {
        id: 'forgot-kit',
        q: 'Or use your emergency kit',
        a: 'If you made a kit, choose <strong>Use Emergency Kit</strong> and type in the pieces from the printed sheets, one per box. Any agreed number of pieces opens the vault (two of three, or the plan you chose); one alone opens nothing.',
      },
      {
        id: 'forgot-none',
        q: 'And if I’ve lost all of them?',
        a: 'Then nobody can open the vault: not you, not us, not anyone. There is no master key, no reset email and no back door, and there never will be. That’s the point. Keep your recovery key on paper, somewhere you’d keep a passport.',
      },
    ],
  },
  {
    title: 'Backups',
    id: 'backups',
    items: [
      {
        id: 'backup-how',
        q: 'How do I back up my vault?',
        a: 'Settings › Data › <strong>Back Up…</strong> makes one file holding the whole vault, still encrypted. Keep it on a disk you plug in. Restoring unpacks it beside your vault and swaps it in with one atomic rename, so a crash midway never leaves you without a vault.',
      },
      {
        id: 'backup-old-password',
        q: 'Does an old backup open with my old password?',
        a: 'Yes. Changing the password, or making a new recovery key or kit, doesn’t re-key the vault: old backups (and Time Machine copies) still open with the old password, key or pieces. Key rotation is planned for 1.x.',
      },
      {
        id: 'export',
        q: 'Can I get everything out as normal files?',
        a: 'Any time: Settings › Data › <strong>Export…</strong> writes every file, note and secret back out as ordinary files in folders. Without the app, <a href="/format/#open-without-us"><code>stillroom-open.py</code></a> does the same.',
      },
    ],
  },
  {
    title: 'Moving to a new Mac',
    id: 'moving',
    items: [
      {
        id: 'move-how',
        q: 'How do I move my vault?',
        a: 'Make a backup on the old Mac, install Stillroom on the new one, and choose <strong>Restore from a Backup…</strong> where it asks you to make a vault. Your licence key works on all of your own Macs.',
      },
      {
        id: 'move-locked',
        q: 'I turned on Lock to this Mac',
        a: 'Then the password alone only opens the vault on the Mac that locked it. On the new Mac, open it with your recovery key or your kit, and set a password there. If you also use a decoy, its password needs its own recovery key once, too.',
      },
      {
        id: 'move-touchid',
        q: 'Touch ID on the new Mac',
        a: 'Touch ID keys live in a Mac’s Secure Enclave and never leave it, so turn Touch ID on again on the new Mac.',
      },
    ],
  },
  {
    title: 'Buying and licences',
    id: 'licences',
    items: [
      {
        id: 'licence-how',
        q: 'How does the licence work?',
        a: 'After you buy, a signed licence key arrives by email. Paste it into Stillroom; it’s checked on your Mac, offline. One licence covers all of one person’s Macs.',
      },
      {
        id: 'refund',
        q: 'Can I get a refund?',
        a: 'Yes: within 14 days, no questions asked. See the <a href="/refunds/">refund policy</a>. Paddle, our reseller, handles refunds.',
      },
      {
        id: 'lost-key',
        q: 'I lost my licence key',
        a: `Write to <a href="mailto:${email.support}">${email.support}</a> from the address you bought with, and we’ll send it again. Losing the licence key never locks you out of your files.`,
      },
    ],
  },
];

/** Plain text for structured data. */
export const plain = (html: string) =>
  html
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ')
    .trim();

export function faqJsonLd(items: QA[]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: items.map((i) => ({
      '@type': 'Question',
      name: i.q,
      acceptedAnswer: { '@type': 'Answer', text: plain(i.a) },
    })),
  };
}
