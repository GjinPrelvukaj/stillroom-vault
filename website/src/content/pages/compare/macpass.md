---
title: 'MacPass Alternative: Stillroom Vault vs MacPass'
description: 'MacPass is a free, open source KeePass app for the Mac. Looking for a MacPass alternative? How Stillroom Vault compares, and when to pick each.'
h1: 'Stillroom Vault vs MacPass'
lead: 'Both are native Mac apps that keep everything in encrypted files on your own computer, with no account. MacPass is a free, open source KeePass client; Stillroom Vault is a vault built around files.'
name: 'MacPass'
updated: '30 October 2026'
order: 77
related: ['/compare/keepassxc/', '/compare/strongbox/', '/compare/offline-password-manager-mac/', '/compare/password-manager-no-subscription/', '/guides/two-factor-codes-on-mac/']
faq:
  - q: 'Is MacPass still maintained?'
    a: 'MacPass 0.8, in February 2022, was its last release with new features. Version 0.8.2, in September 2026, moved the app to a new web address, macpass.app, after the old domain was dropped. Its README says MacPass fell behind in features and hopes to revive it.'
  - q: 'Is MacPass free?'
    a: 'Yes. MacPass is free and open source under the GPLv3. It isn''t on the Mac App Store, because of that licence; releases are published on GitHub.'
  - q: 'Does MacPass support two-factor codes?'
    a: 'Yes. Since version 0.8, MacPass shows time-based (TOTP) codes, including Steam codes, stored in KeePass entries.'
  - q: 'How do I move from MacPass to Stillroom Vault?'
    a: 'MacPass exports KeePass XML, and Stillroom imports CSV. Open your .kdbx file in KeePassXC, which is free, export a CSV from there, and import that into Stillroom. Save attachments separately and drag them in.'
sources:
  - label: 'MacPass: home page'
    url: 'https://macpass.app/'
  - label: 'MacPass on GitHub'
    url: 'https://github.com/MacPass/MacPass'
  - label: 'MacPass: Releases'
    url: 'https://github.com/MacPass/MacPass/releases'
  - label: 'MacPass wiki: Status'
    url: 'https://github.com/MacPass/MacPass/wiki/Status'
  - label: 'KeePassXC: User Guide'
    url: 'https://keepassxc.org/docs/KeePassXC_UserGuide'
---

## What MacPass is, and who it suits

MacPass is a free, open source password manager for macOS, licensed under the GPLv3. It's a KeePass client: it opens and saves KeePass databases (the older KDB format, and KDBX up to 4.1), so the same file works in KeePassXC, Strongbox and other KeePass apps. Its README calls it the only native macOS KeePass client that is fully open source.

Entries hold usernames, passwords, URLs, notes and attachments, which you add by dropping files onto an entry and can preview with Quick Look. MacPass shows two-factor (TOTP) codes, and Auto-Type fills credentials into text fields in any app, with an optional system-wide shortcut. It can merge changes made to the same database elsewhere, and plugins extend it.

There's no built-in sync and no phone app. Like any KeePass database, the file can sit in a cloud folder you choose, and other KeePass apps can open it on a phone.

Development has been slow. Version 0.8, in February 2022, brought KDBX 4.1, Argon2id, TOTP and native Apple silicon support, and was the last release with new features. Version 0.8.2, in September 2026, moved MacPass to a new web address after the old domain, macpassapp.org, was dropped; the README asks everyone to update and to download only from GitHub. It also says plainly that MacPass fell behind in interface and features, and that the developer hopes to revive it.

It suits people who want a free, native, open source Mac app for a KeePass database they already use, and who are happy with how it works today.

## Side by side

| What | MacPass | Stillroom Vault |
|---|---|---|
| Where data lives | One `.kdbx` file, wherever you put it | One folder on your Mac |
| Encryption | KeePass formats; Argon2id in KDBX 4; optional key file | AES-256-GCM, a fresh key per item; Argon2id (512 MB) |
| Platforms | macOS 10.13 or later; other KeePass apps elsewhere | Apple silicon Macs, macOS 26 or later |
| Price | Free | Free for 25 items; $39 once; Family $79 once for 5 people |
| Source | Open source (GPLv3) | Source available (FSL); the reader script is MIT |
| Cloud and sync | None built in; store the file in a cloud folder if you want | None; it never goes online |
| Scope | Password manager, with attachments | File vault that also holds passwords and two-factor codes |

## Where MacPass is the better choice

- **It's free, with no limit.** Stillroom's free tier holds 25 items.
- **The KeePass format.** Your database opens in KeePassXC on Windows and Linux, and in KeePass apps on your phone. Stillroom's [format is public](/format/) and a short Python script reads it without the app, but no other password manager opens it.
- **Auto-Type.** MacPass can type a username and password into another app's fields for you. Stillroom doesn't fill anything; you copy a password, and it clears from the clipboard after 30 seconds if nothing else was copied since.
- **Older Macs.** MacPass 0.8 runs on macOS 10.13 or later. Stillroom needs Apple silicon and macOS 26 or later.
- **Key files.** A KeePass key file can be required alongside your password.
- **Fully open source.** Stillroom's source is published under the Functional Source License, which isn't an open source licence, and Stillroom hasn't had an independent security audit yet; one is planned.

## Where Stillroom Vault fits better

MacPass and Stillroom share a lot: native Mac apps, your data in encrypted files on your own computer, no account and no company server. The differences are what each holds, and how actively each is being built.

- **Files are first-class.** In a KeePass database, attachments are stored inside the one database file, so large ones make that file grow. Stillroom keeps files of any kind and size as separate sealed items, with folders, tags, earlier versions and a sealed search index. Items over 8 MB, and all audio and video, are stored in chunks that stream.
- **Viewing doesn't write a decrypted copy to disk.** PDFs, images, text, sketches and email open in built-in viewers, and audio and video play straight from the sealed file. Other previews, and Edit in Place, use a RAM disk. The app you edit in may keep copies of its own; Stillroom warns about this.
- **Built for the current macOS.** Stillroom is a new app made for macOS 26 and Apple silicon, with 1.x updates included in the licence.
- **No network code at all.** Stillroom makes no network connections, and a build check fails any version that links networking code.
- **Ways back in for people, not just files.** A [recovery key](/features/recovery-key/), and a printable [emergency kit](/features/emergency-kit/) split into pieces so that any agreed number of trusted people can open the vault together. Plus [Touch ID](/features/touch-id/) through the Secure Enclave and optional [Lock to this Mac](/features/lock-to-this-mac/). Nobody can recover a forgotten password, so set these up early.
- **Protection at the keyboard.** A [decoy password](/features/decoy-password/), an [intruder log](/features/intruder-log/), and windows [hidden from screen capture](/features/hidden-from-capture/). The decoy protects against thieves and abusers, not police, and doesn't fool someone who has one password and a copy of the vault folder ([rule 2](/security/#rules)).
- **A fixed, heavy password stretch.** Stillroom always uses Argon2id with 512 MB of memory, 3 passes and 4 lanes, and refuses guessable passwords. In a KeePass file the stretch depends on the settings the database was made with. [Argon2id, explained](/learn/argon2id/) covers why the stretch helps but doesn't make a weak password safe.
- **A Mac app that locks itself.** It locks on sleep, after a while, or with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> from any app, and can delete originals you add once each copy is read back and checked by SHA-256.

## Using both, or moving over

They sit together well. Keep your KeePass database in MacPass, or in whichever KeePass app you use on your phone. Keep documents, ID scans, recordings and private notes in Stillroom. Stillroom can also be a separate place for two-factor setups and backup codes, so that one database never holds every factor; [two-factor codes on your Mac](/guides/two-factor-codes-on-mac/) and [storing two-factor backup codes](/guides/store-two-factor-backup-codes/) cover the options.

To move passwords across, you need a CSV file. MacPass exports KeePass XML, and Stillroom imports CSV, so go through KeePassXC, which is free and opens the same database:

1. Open your `.kdbx` file in KeePassXC with your usual password (and key file, if you use one).
2. In KeePassXC, export the database as a CSV file.
3. In Stillroom, import the file. Stillroom's importer was written for Apple Passwords, browser, Bitwarden and 1Password exports and matches columns by name, so open a few entries afterwards to check the site, username, password and notes came through.
4. KeePassXC's CSV export doesn't include attachments, so save those from MacPass and drag them into Stillroom.
5. Delete the CSV and empty the Trash: KeePassXC warns that an export is unencrypted.

Your database is untouched by all this, so keep it until you've checked that everything you need is in Stillroom.
