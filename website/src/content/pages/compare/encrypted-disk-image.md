---
title: 'Stillroom Vault vs an Encrypted Disk Image'
description: 'macOS can make a password-protected disk image for free. When that is enough, and when Stillroom Vault is worth it for files, notes and passwords.'
h1: 'Stillroom Vault vs an encrypted disk image'
lead: 'Every Mac can already make an encrypted disk image in Disk Utility, for free. Here is what it does well, and what Stillroom Vault adds.'
name: 'Encrypted disk image'
updated: '27 October 2026'
order: 30
related: ['/guides/password-protect-a-folder-on-mac/', '/guides/encrypt-files-on-mac/', '/compare/veracrypt/', '/features/view-without-decrypting/']
faq:
  - q: 'How do I make an encrypted disk image on a Mac?'
    a: 'In Disk Utility, choose File, New Image, Blank Image, pick an encryption option and a read/write format, and set a password. Apple''s guide walks through it.'
  - q: 'What happens if I forget a disk image''s password?'
    a: 'Apple says you won''t be able to open the image or see its files. The same is true of Stillroom Vault, though it also gives you a recovery key and an optional emergency kit.'
  - q: 'Is a disk image enough for most people?'
    a: 'For a folder of documents you open now and then, often yes. Stillroom Vault is worth it when you also want passwords and two-factor codes, viewers that don''t leave copies, more ways back in, or a vault that locks itself.'
sources:
  - label: 'Apple: Create a disk image using Disk Utility on Mac'
    url: 'https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac'
  - label: 'Apple: Protect data on your Mac with FileVault'
    url: 'https://support.apple.com/guide/mac-help/mh11785/mac'
---

## What an encrypted disk image is

An encrypted disk image is a single file that holds a small, password-protected disk. You make one in Disk Utility, which comes with every Mac: choose **File > New Image > Blank Image**, pick a size, an encryption option and a read/write format, and set a password. Double-click the file, type the password, and it appears in Finder as a drive. Copy documents into it, eject it, and they're locked again.

Apple's own guide describes it as a way to keep confidential documents where others can't see them without your permission. It's free, it's built in, and it uses no third-party software. For a folder of scans you open a few times a year, it may be all you need, and we'd rather say so.

It also helps to know what's already protecting you. FileVault protects everything on your Mac's startup disk behind your login password. A disk image or a vault app adds a second lock for particular files while the Mac is on and you're logged in.

## Side by side

| What | Encrypted disk image | Stillroom Vault |
|---|---|---|
| Where data lives | One image file, wherever you save it | One folder on your Mac |
| Encryption | An encryption option you choose in Disk Utility | AES-256-GCM, a fresh key per item; Argon2id (512 MB) for the password |
| Platforms | Any Mac | Apple silicon Macs, macOS 26 or later |
| Price | Free, built in | Free for 25 items; $39 once; Family $129 for 5 people |
| Source | Part of macOS | Source available (FSL); the reader script is MIT |
| Cloud and sync | None; you can copy the file anywhere | None; it never goes online |
| Scope | Any files | Files, notes, passwords and two-factor codes |

## Where a disk image is the better choice

- **It's free and already there.** Nothing to install, buy or trust beyond macOS itself.
- **It works on older Macs.** Stillroom needs Apple silicon and macOS 26 or later.
- **Any app works on the files directly.** A mounted image is an ordinary drive, so you can open, edit and save in place.
- **You can move it.** The image is one file you can copy to a drive or another Mac and open there with its password.
- **There's no item limit.** Stillroom's free tier holds 25 items.

## Where Stillroom Vault fits better

A disk image is a locked box. Stillroom is a place to work with what's inside without spreading it around.

- **It locks itself.** Apple's guide reminds you that a mounted image stays accessible on your desktop until you eject it. Stillroom locks after a while, when the Mac sleeps, and with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> from any app.
- **Viewing doesn't write a decrypted copy to disk.** PDFs, images, text, sketches and email open in built-in viewers, audio and video stream from the sealed file, and other previews go to a RAM disk. When you need another app, Edit in Place opens the file from the RAM disk and seals your changes back; that app may still keep copies of its own, and Stillroom warns about this. See [view without decrypting](/features/view-without-decrypting/).
- **Passwords and two-factor codes, too.** Secrets are records with fields, and any secret holding a two-factor setup shows its live code. Copied secrets stay off Universal Clipboard and clear after 30 seconds.
- **Names stay hidden.** Inside Stillroom, names, folders, kinds and tags are sealed. Someone with a copy of the vault sees how many items there are, their rough sizes and when they were added, and that's all; the [security page](/security/) lists it exactly.
- **More ways back in.** A disk image has one password. Stillroom adds a [recovery key](/features/recovery-key/), a printable [emergency kit](/features/emergency-kit/) you can split between people you trust, and [Touch ID](/features/touch-id/).
- **Protection at the keyboard.** A [decoy password](/features/decoy-password/), an [intruder log](/features/intruder-log/), and windows [hidden from screen capture](/features/hidden-from-capture/). The decoy protects against thieves and abusers, not police, and doesn't fool someone with one password and a copy of the folder ([rule 2](/security/#rules)).
- **Search, folders, tags and versions.** Search covers names and contents, from a word index that is sealed too, and every item keeps its earlier versions.

Stillroom also stretches your password with Argon2id using 512 MB of memory, which makes each guess slow and costly. That helps, but the password's own strength is still what matters most, which is why Stillroom refuses guessable ones.

## Using both, or moving over

Many people use both. A disk image is a good way to hand someone a set of files on a USB stick. Stillroom is where things live day to day.

To move a disk image's contents into Stillroom:

1. Double-click the image and enter its password.
2. Drag its files or folders into Stillroom's window. Folders keep their structure.
3. Open a few items in Stillroom to check them, then eject the image.
4. When you're sure, delete the image file and empty the Trash.

Stillroom can also delete the originals for you, but only after it has read each copy back and checked it by SHA-256. It never "secure-erases": on an SSD that does nothing. FileVault is what keeps deleted data unreadable, and Stillroom warns when it's off.

Neither a disk image nor Stillroom can recover a forgotten password. Apple says so for disk images, and with Stillroom, only your recovery key or emergency kit can open the vault. The [password-protect a folder](/guides/password-protect-a-folder-on-mac/) guide compares the built-in options step by step.
