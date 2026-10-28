---
title: 'Stillroom Vault vs Apple Notes Locked Notes'
description: 'Apple Notes can lock a note with a password, free and synced through iCloud. What it covers, what it can''t lock, and when Stillroom Vault fits better.'
h1: 'Stillroom Vault vs locked notes in Apple Notes'
lead: 'Locked notes are free, encrypted and on every Apple device you own. They also have limits worth knowing before you trust them with documents.'
name: 'Apple Notes locked notes'
updated: '27 October 2026'
order: 40
related: ['/moving-from/apple-passwords/', '/guides/keep-id-scans-safe/', '/guides/store-two-factor-backup-codes/', '/compare/encrypted-disk-image/']
faq:
  - q: 'Are locked notes in Apple Notes encrypted?'
    a: 'Yes. Apple''s Platform Security guide says locked notes are end-to-end encrypted with a key derived from your passphrase, and the note and its attachments are encrypted with AES-GCM.'
  - q: 'Can I lock a note with a PDF in it?'
    a: 'No. Apple says notes with a video, audio file, PDF or document attached can''t be locked. Images, scans, drawings and tables are allowed.'
  - q: 'What if I forget my locked notes password?'
    a: 'Apple says that if you forget a custom password and can''t use Touch ID, you can''t view those notes, and Apple can''t restore access. Stillroom Vault is the same: nobody can recover a forgotten password, which is why it gives you a recovery key and an optional emergency kit.'
sources:
  - label: 'Apple: Lock your notes on Mac'
    url: 'https://support.apple.com/guide/notes/not28c5f5468/mac'
  - label: 'Apple Platform Security: Secure features in the Notes app'
    url: 'https://support.apple.com/guide/security/sec1782bcab1/web'
  - label: 'Apple: Passwords User Guide'
    url: 'https://support.apple.com/guide/passwords/welcome/mac'
---

## What locked notes are, and who they suit

The Notes app on your Mac can lock individual notes. You choose either your Mac login password or a separate password just for locked notes, and you can turn on Touch ID to open them. Locked notes close again after a while or when you quit Notes.

The protection is real. Apple's Platform Security guide says locked notes are end-to-end encrypted with a key derived from your passphrase (PBKDF2 with SHA-256), and that the note's text and attachments are encrypted with AES-GCM. Notes stored in iCloud stay locked on your other devices too.

Locked notes suit you if you want a few private notes, such as a door code or a medical detail, on your iPhone and Mac, with nothing to install or pay for. For passwords and verification codes, Apple's free Passwords app is the built-in choice, and it's worth using before you pay for anything.

## Side by side

| What | Apple Notes locked notes | Stillroom Vault |
|---|---|---|
| Where data lives | On your Mac, or in iCloud | One folder on your Mac |
| Encryption | AES-GCM, key from your passphrase with PBKDF2 | AES-256-GCM, a fresh key per item; Argon2id (512 MB) for the password |
| Platforms | Mac, iPhone, iPad, and the iCloud website | Apple silicon Macs, macOS 26 or later |
| Price | Free, built in | Free for 25 items; $39 once; Family $129 for 5 people |
| Source | Part of macOS and iOS | Source available (FSL); the reader script is MIT |
| Cloud and sync | Through iCloud | None; it never goes online |
| Scope | Notes, with images, scans and drawings | Files of any kind, notes, passwords and two-factor codes |

## Where locked notes are the better choice

- **They're on your iPhone.** A locked note in iCloud opens on your phone, your iPad and your Mac. Stillroom runs only on the Mac and has no sync.
- **They're free and already there.** No app to install, no licence, no item limit.
- **Your login password can open them.** Using the Mac login password means one less password to remember.
- **Short notes are what Notes does best.** Typing a quick note on your phone and locking it takes seconds.

## Where Stillroom Vault fits better

Apple lists what can't be locked, and the list matters for the things people most want to protect:

- notes with a **PDF**, a **document**, a **video** or an **audio file** attached
- notes shared with other people
- notes that contain tags
- Quick Notes

So a passport scan saved as a PDF, a signed contract or a voice memo can't sit in a locked note. Stillroom keeps files of any kind. PDFs, images, sketches, text and email open in its own viewers, and audio and video play straight from the sealed file, without writing a decrypted copy to disk.

Other differences:

- **Nothing leaves the Mac.** Stillroom makes no network connections at all. Locked notes in iCloud are end-to-end encrypted, but they're still stored with Apple. If you'd rather nothing were, Stillroom is built for that.
- **Passwords and two-factor codes in the same place.** Secrets are records with fields, and any secret holding a two-factor setup shows its live code. You can import from Apple Passwords, browsers, Bitwarden and 1Password exports. See [storing two-factor backup codes](/guides/store-two-factor-backup-codes/).
- **More ways back in.** A forgotten custom password locks you out of locked notes for good. Stillroom can't recover a forgotten password either, so it makes a [recovery key](/features/recovery-key/) with every vault and offers a printable [emergency kit](/features/emergency-kit/) you can split among people you trust.
- **A slower password to guess.** Stillroom stretches your password with Argon2id using 512 MB of memory and 3 passes. The password's strength still matters most, so Stillroom refuses guessable ones.
- **Names stay hidden.** In Stillroom, names, folders and tags are sealed along with the contents.
- **Protection at the keyboard.** Auto-lock, a [decoy password](/features/decoy-password/), an [intruder log](/features/intruder-log/), and windows [hidden from screen capture](/features/hidden-from-capture/). The decoy protects against thieves and abusers, not police, and doesn't fool someone with one password and a copy of the vault folder ([rule 2](/security/#rules)).

## Using both, or moving over

Using both is a sensible split. Keep everyday notes you want on your phone in Notes, locked or not. Keep documents, ID scans, recovery codes and passwords in Stillroom.

To move a locked note into Stillroom:

1. Open the locked note in Notes.
2. In Stillroom, make a new note and paste the text in, or drag images out of Notes and into Stillroom's window.
3. Check it in Stillroom, then delete the note in Notes, and delete it from Recently Deleted too.

For passwords in Apple's Passwords app, export them to a file, import that file into Stillroom, then delete the export: it isn't encrypted. Stillroom reads the export in memory and never writes it out. The [moving from Apple Passwords](/moving-from/apple-passwords/) guide goes step by step, and [keeping ID scans safe](/guides/keep-id-scans-safe/) covers documents.
