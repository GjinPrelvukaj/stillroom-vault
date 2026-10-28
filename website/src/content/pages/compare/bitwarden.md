---
title: 'Stillroom Vault vs Bitwarden'
description: 'Bitwarden is an open source, cross-platform password manager with a free plan. Stillroom Vault is an offline Mac vault for files and secrets.'
h1: 'Stillroom Vault vs Bitwarden'
lead: 'Bitwarden is an open source password manager that syncs to every device, with a generous free plan. Stillroom Vault is a Mac vault that never goes online. Here is how to choose, or use both.'
name: 'Bitwarden'
updated: '27 October 2026'
order: 60
related: ['/moving-from/bitwarden/', '/compare/1password/', '/compare/keepassxc/', '/guides/store-two-factor-backup-codes/']
faq:
  - q: 'Is Bitwarden free?'
    a: 'Bitwarden has a free plan with no limit on passwords or devices. Premium adds features such as the built-in authenticator, emergency access and encrypted file storage, and a Families plan covers up to six people.'
  - q: 'Can I import my Bitwarden passwords into Stillroom Vault?'
    a: 'Yes. Export your vault from Bitwarden as a CSV file, import it into Stillroom, then delete the export. Stillroom imports logins; cards and secure notes in the export are left out.'
  - q: 'Can I self-host Bitwarden instead?'
    a: 'Yes. Bitwarden says you can run its server on your own network or server. That keeps sync but moves the server to you; Stillroom has no server at all.'
sources:
  - label: 'Bitwarden: Pricing'
    url: 'https://bitwarden.com/pricing/'
  - label: 'Bitwarden: Security white paper'
    url: 'https://bitwarden.com/help/bitwarden-security-white-paper/'
  - label: 'Bitwarden: Download'
    url: 'https://bitwarden.com/download/'
  - label: 'Bitwarden: Export vault data'
    url: 'https://bitwarden.com/help/export-your-data/'
---

## What Bitwarden is, and who it suits

Bitwarden is an open source password manager. It has apps for Windows, macOS and Linux, iPhone and Android, a web vault, a command-line tool, and browser extensions for Chrome, Safari, Firefox, Edge, Brave, Opera, Vivaldi and others. It saves and fills your logins, and syncs them between all your devices.

Its security white paper describes zero-knowledge, end-to-end encryption: your vault is encrypted on your device before it syncs, so Bitwarden can't read it. It uses AES-256 with HMAC authentication, and stretches your master password with PBKDF2 (600,000 iterations by default) or, if you choose, Argon2id. The source code is on GitHub, and Bitwarden says third-party security reviews happen at least once a year.

The free plan has no limit on passwords or devices. Premium adds a built-in authenticator for two-factor codes, emergency access, security reports and encrypted file storage. A Families plan covers up to six people, and you can self-host the server if you prefer.

It suits almost anyone who needs a password manager across several devices, especially if you value open source and a free plan. For many people it, or Apple's free Passwords app, is where everyday logins belong.

## Side by side

| What | Bitwarden | Stillroom Vault |
|---|---|---|
| Where data lives | Your devices, plus Bitwarden's cloud or your own server | One folder on your Mac |
| Encryption | End-to-end, AES-256 with HMAC; PBKDF2 or Argon2id | AES-256-GCM, a fresh key per item; Argon2id (512 MB) |
| Platforms | Windows, macOS, Linux, iOS, Android, web, browser extensions, CLI | Apple silicon Macs, macOS 26 or later |
| Price | Free plan; paid Premium and Families plans | Free for 25 items; $39 once; Family $129 once for 5 people |
| Source | Open source | Source available (FSL); the reader script is MIT |
| Cloud and sync | Built in, or self-hosted | None; it never goes online |
| Scope | Password manager, with file storage on paid plans | File vault that also holds passwords and two-factor codes |

## Where Bitwarden is the better choice

- **Autofill and every device.** Bitwarden fills logins in your browser and on your phone, and keeps them in step everywhere. Stillroom has no autofill, no phone app and no sync.
- **Free for unlimited passwords.** Stillroom's free tier holds 25 items in total.
- **Open source and audited.** Bitwarden's code is open source and reviewed by outside firms every year. Stillroom's source is published under the Functional Source License, which isn't an open source licence, and Stillroom hasn't had an independent security audit yet; one is planned.
- **Sharing.** Premium can share with one other person, and Families has unlimited sharing. Stillroom has no sharing; each person's vault is their own.
- **Windows and Linux.** Stillroom runs only on Apple silicon Macs.

## Where Stillroom Vault fits better

- **Documents are the point.** Stillroom holds files of any kind, with folders, tags, earlier versions and a sealed search index. PDFs, images, text, sketches and email open in built-in viewers, and audio and video play straight from the sealed file, without writing a decrypted copy to disk. Other previews go to a RAM disk.
- **No server, not even your own.** Self-hosting moves Bitwarden's server to you; Stillroom has none. It makes no network connections, and a build check fails any version that links networking code.
- **Pay once.** $39 for all of one person's Macs, or $129 for a family of five, with every 1.x update included. The free tier never blocks opening, exporting or backing up.
- **More ways back in, held by you.** A [recovery key](/features/recovery-key/), a printable [emergency kit](/features/emergency-kit/) split among people you trust, [Touch ID](/features/touch-id/), and optional [Lock to this Mac](/features/lock-to-this-mac/). Nobody, us included, can recover a forgotten password.
- **Protection at the keyboard.** A [decoy password](/features/decoy-password/), an [intruder log](/features/intruder-log/), and windows [hidden from screen capture](/features/hidden-from-capture/). The decoy protects against thieves and abusers, not police, and doesn't fool someone who has one password and a copy of the vault folder ([rule 2](/security/#rules)).
- **A heavier password stretch.** Stillroom always uses Argon2id with 512 MB of memory, 3 passes and 4 lanes. That slows guessing, but your password's strength is still what matters most, and Stillroom refuses guessable ones.

## Using both, or moving over

A common setup is Bitwarden for everyday logins, with autofill on every device, and Stillroom for what should stay on one Mac: your Bitwarden master password and recovery code, two-factor backup codes, ID scans, contracts and private notes. Keeping backup codes apart from the passwords they protect means no single place holds every factor; [storing two-factor backup codes](/guides/store-two-factor-backup-codes/) explains the trade-offs.

To move your logins into Stillroom:

1. In Bitwarden, export your vault as a CSV file.
2. In Stillroom, import the file. Each login becomes a Login secret with its site, username, password and notes, and any two-factor setup is kept as a concealed field. Cards and secure notes in the export are left out, so copy those across by hand.
3. Delete the export and empty the Trash: a CSV export is plain text, and Bitwarden advises deleting it promptly. Stillroom reads it in memory and never writes it out.

A CSV export doesn't include attachments, so save attached files from Bitwarden and drag them into Stillroom. The [moving from Bitwarden](/moving-from/bitwarden/) guide goes step by step.
