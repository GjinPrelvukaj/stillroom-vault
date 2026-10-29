// The site's article sections: pages written in src/content/pages/<section>/<slug>.md, each with a hub page that
// lists them. Features has no hub of its own: its pages are listed on /features/.
export const sections = {
  compare: {
    name: 'Comparisons',
    eyebrow: 'Compare',
    title: 'Stillroom Vault Compared: Cryptomator, VeraCrypt, 1Password and More',
    h1: 'How Stillroom Vault compares',
    description:
      'Stillroom Vault next to Cryptomator, VeraCrypt, an encrypted disk image, Apple Notes, 1Password, Bitwarden and others: what each does well, and when to choose it.',
    lead: 'Fair comparisons with the tools people already use. Each says what the other one does better, and when you should pick it.',
  },
  guides: {
    name: 'Guides',
    eyebrow: 'Guides',
    title: 'Guides: Keeping Files Private on a Mac',
    h1: 'Guides to keeping files private on your Mac',
    description:
      'Step-by-step guides: password-protect a folder on a Mac, encrypt files, hide photos, keep ID scans and two-factor backup codes safe, and what to do if a Mac is stolen.',
    lead: 'How to protect what’s on your Mac, with the free ways built into macOS first and Stillroom Vault where it does more.',
  },
  features: {
    name: 'Features',
    eyebrow: 'Feature',
    title: 'Features',
    h1: 'Features',
    description: '',
    lead: '',
  },
  'moving-from': {
    name: 'Moving to Stillroom',
    eyebrow: 'Moving to Stillroom',
    title: 'Move to Stillroom Vault from Apple Passwords, 1Password, Bitwarden and More',
    h1: 'Moving to Stillroom Vault',
    description:
      'Bring your passwords and files into Stillroom Vault from Apple Passwords, Chrome, Firefox, Bitwarden, 1Password, Cryptomator or VeraCrypt, step by step.',
    lead: 'Step by step, from the app you use today. Exports are read in memory, and you can delete the export file once it’s in.',
  },
  learn: {
    name: 'Learn',
    eyebrow: 'Learn',
    title: 'Encryption Explained: AES-256-GCM, Argon2id, Shamir and More',
    h1: 'The ideas behind an encrypted vault',
    description:
      'Plain explanations of AES-256-GCM, Argon2id, Shamir secret sharing, the Secure Enclave and plausible deniability, and how Stillroom Vault uses each.',
    lead: 'The ideas a vault rests on, explained without the jargon, and how Stillroom Vault uses each one.',
  },
  for: {
    name: 'Who it’s for',
    eyebrow: 'Who it’s for',
    title: 'Who Stillroom Vault Is For: Lawyers, Clinics, Journalists, Travellers',
    h1: 'Who Stillroom Vault is for',
    description:
      'How lawyers, medical practices, journalists, travellers and people leaving an abusive relationship can keep files private on a Mac with Stillroom Vault, and its limits.',
    lead: 'For people whose files would hurt someone if they got out, with what it protects against and what it doesn’t.',
  },
  tools: {
    name: 'Free tools',
    eyebrow: 'Free tools',
    title: 'Free Privacy Tools: Passphrases, 2FA Codes, Checksums',
    h1: 'Free tools that never leave your browser',
    description:
      'Free tools for passwords, passphrases, PINs, two-factor codes, QR codes, file checksums and Shamir secret sharing. They run in your browser and send nothing.',
    lead: 'Small tools for the jobs around passwords and two-factor codes. Each one runs in your browser, on your device: nothing you type or drop on these pages is sent anywhere.',
  },
} as const;

export type Section = keyof typeof sections;
/** The faint artwork beside each section's headings. */
export const sectionArt = { compare: 'pair', guides: 'path', features: 'ring', 'moving-from': 'arrive', learn: 'lit', for: 'ring', tools: 'lit' } as const;
export const hubSections = (Object.keys(sections) as Section[]).filter((s) => s !== 'features');
