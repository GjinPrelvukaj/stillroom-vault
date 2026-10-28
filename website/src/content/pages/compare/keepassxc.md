---
title: 'Stillroom Vault vs KeePassXC'
description: 'KeePassXC is a free, open source, offline password manager for Windows, macOS and Linux. How it compares with Stillroom Vault, and when to pick each.'
h1: 'Stillroom Vault vs KeePassXC'
lead: 'Both keep everything in an encrypted file on your own computer, with no cloud account. KeePassXC is a free, open source password manager; Stillroom Vault is a Mac vault built around files.'
name: 'KeePassXC'
updated: '27 October 2026'
order: 70
related: ['/compare/bitwarden/', '/compare/1password/', '/guides/store-two-factor-backup-codes/', '/learn/argon2id/']
faq:
  - q: 'Is KeePassXC free?'
    a: 'Yes. KeePassXC is free and open source under the GPLv3, for Windows, macOS and Linux, with no subscription.'
  - q: 'Does KeePassXC have a phone app?'
    a: 'Not an official one. KeePassXC''s documentation suggests KeePassDX or KeePass2Android on Android, and Strongbox or KeePassium on iOS, which open the same database file.'
  - q: 'Can I move my KeePassXC passwords into Stillroom Vault?'
    a: 'KeePassXC can export a CSV file, and Stillroom imports CSV password exports. Stillroom''s importer is built around Apple Passwords, browser, Bitwarden and 1Password exports, so check a few entries afterwards. Attachments aren''t in KeePassXC''s CSV export.'
sources:
  - label: 'KeePassXC: home page'
    url: 'https://keepassxc.org/'
  - label: 'KeePassXC: Documentation and FAQ'
    url: 'https://keepassxc.org/docs/'
  - label: 'KeePassXC: User Guide'
    url: 'https://keepassxc.org/docs/KeePassXC_UserGuide'
---

## What KeePassXC is, and who it suits

KeePassXC is a free, open source password manager for Windows, macOS and Linux, licensed under the GPLv3. It keeps your passwords in an encrypted database file (a `.kdbx` file) that you can store wherever you like. Its site says no data is stored on remote servers, and there are no ads and no subscriptions.

The database is encrypted with AES-256 or Twofish. With the recommended KDBX 4 format, your master password is stretched with Argon2, and you can add a key file or a YubiKey as a second factor. Entries hold usernames, passwords, URLs, notes and attachments, and KeePassXC can show two-factor (TOTP) codes, store passkeys, act as an SSH agent, and fill logins in Firefox, Chrome, Chromium and Vivaldi through its browser extension.

There's no built-in sync and no official phone app. If you want the database on several devices, you put the file in a cloud folder you choose, and open it on your phone with a compatible app such as KeePassDX, KeePass2Android, Strongbox or KeePassium.

It suits people who want a password manager they control completely, on any desktop system, without paying or creating an account.

## Side by side

| What | KeePassXC | Stillroom Vault |
|---|---|---|
| Where data lives | One `.kdbx` file, wherever you put it | One folder on your Mac |
| Encryption | AES-256 or Twofish; Argon2 in KDBX 4; optional key file or YubiKey | AES-256-GCM, a fresh key per item; Argon2id (512 MB) |
| Platforms | Windows, macOS, Linux; phone apps from other developers | Apple silicon Macs, macOS 26 or later |
| Price | Free | Free for 25 items; $39 once; Family $129 once for 5 people |
| Source | Open source (GPLv3) | Source available (FSL); the reader script is MIT |
| Cloud and sync | None built in; store the file in a cloud folder if you want | None; it never goes online |
| Scope | Password manager, with attachments | File vault that also holds passwords and two-factor codes |

## Where KeePassXC is the better choice

- **It's free, with no limit.** Stillroom's free tier holds 25 items.
- **It runs everywhere on the desktop.** Windows, macOS and Linux. Stillroom needs an Apple silicon Mac with macOS 26 or later.
- **Browser autofill.** KeePassXC-Browser fills logins in supported browsers, and Auto-Type fills them in other apps. Stillroom doesn't fill anything; you copy and paste.
- **Your choice of sync and phone app.** The database is one file, so you can sync it through any service you like and open it with other KeePass apps. Stillroom has no sync and no phone app.
- **Hardware keys.** A YubiKey or key file can be required alongside your password.
- **Fully open source.** Stillroom's source is published under the Functional Source License, which isn't an open source licence, and Stillroom hasn't had an independent security audit yet; one is planned.
- **Developer tools.** The SSH agent integration is useful if you manage SSH keys.

## Where Stillroom Vault fits better

KeePassXC and Stillroom share a lot of the same thinking: your data in an encrypted file on your own computer, no account and no company server. The difference is what each is built to hold.

- **Files are first-class.** KeePassXC stores attachments inside entries, and its guide notes that large attachments make the database grow. Stillroom keeps files of any kind and size as separate sealed items, with folders, tags, earlier versions and a sealed search index. Items over 8 MB, and all audio and video, are stored in chunks that stream.
- **Viewing doesn't write a decrypted copy to disk.** PDFs, images, text, sketches and email open in built-in viewers, and audio and video play straight from the sealed file. Other previews, and Edit in Place, use a RAM disk. The app you edit in may keep copies of its own; Stillroom warns about this.
- **No network code at all.** Stillroom makes no network connections, and a build check fails any version that links networking code.
- **Ways back in for people, not just files.** A [recovery key](/features/recovery-key/), and a printable [emergency kit](/features/emergency-kit/) split into pieces so that any agreed number of trusted people can open the vault together. Plus [Touch ID](/features/touch-id/) through the Secure Enclave and optional [Lock to this Mac](/features/lock-to-this-mac/). Nobody can recover a forgotten password, so set these up early.
- **Protection at the keyboard.** A [decoy password](/features/decoy-password/), an [intruder log](/features/intruder-log/), and windows [hidden from screen capture](/features/hidden-from-capture/). The decoy protects against thieves and abusers, not police, and doesn't fool someone who has one password and a copy of the vault folder ([rule 2](/security/#rules)).
- **A Mac app that behaves like one.** It locks on sleep, after a while, or with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> from any app, and can delete originals you add once each copy is read back and checked by SHA-256.

Both are honest about their limits in the same way: a strong password is the real boundary. [Argon2id, explained](/learn/argon2id/) covers why the stretch helps but doesn't make a weak password safe.

## Using both, or moving over

They sit together well. Keep logins in KeePassXC, with its browser integration and sync through a folder you pick. Keep documents, ID scans, recordings and private notes in Stillroom.

KeePassXC's guide makes a point worth repeating: storing two-factor codes in the same database as the passwords removes some of the benefit of two-factor, and it suggests a separate database for them if you want the most security. Stillroom can be that separate place for two-factor setups and backup codes; [storing two-factor backup codes](/guides/store-two-factor-backup-codes/) covers how.

To move passwords across, export a CSV from KeePassXC and import it into Stillroom. Stillroom's importer was written for Apple Passwords, browser, Bitwarden and 1Password exports and matches columns by name, so open a few entries afterwards to check the site, username, password and notes came through. KeePassXC's CSV export doesn't include attachments, so save those from KeePassXC and drag them into Stillroom. Then delete the CSV: KeePassXC warns that an export is unencrypted.
