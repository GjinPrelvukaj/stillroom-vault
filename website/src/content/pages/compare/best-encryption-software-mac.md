---
title: 'Best Encryption Software for Mac in 2026'
description: 'FileVault, Disk Utility, Cryptomator, VeraCrypt, Encrypto, AxCrypt and Stillroom Vault compared: price, what each encrypts, which job it suits.'
h1: 'The best encryption software for Mac in 2026'
lead: 'There is no single best encryption app for a Mac, because "encrypt my files" means different jobs. Here are the tools worth knowing, free ones first, checked on 30 October 2026, and which job each one does well.'
name: 'Best encryption software for Mac'
updated: '30 October 2026'
order: 9
points:
  - '**Start with FileVault.** It''s free, built in, and protects the whole Mac when it''s off.'
  - '**For files in a cloud folder,** Cryptomator. **For drives that move between systems,** VeraCrypt.'
  - '**For one file to send,** a disk image, Encrypto or a PDF password. **For a private vault on one Mac,** an app such as Stillroom Vault.'
related: ['/compare/filevault/', '/guides/encrypt-files-on-mac/', '/compare/encrypted-disk-image/', '/compare/cryptomator/', '/compare/veracrypt/', '/compare/offline-password-manager-mac/']
faq:
  - q: 'What is the best free encryption software for Mac?'
    a: 'For most people, the free tools built into macOS: FileVault for the whole disk and an encrypted disk image from Disk Utility for a set of files. Cryptomator and VeraCrypt are free and open source if you need cloud folders or cross-platform drives.'
  - q: 'Does a Mac have built-in file encryption?'
    a: 'Yes. FileVault protects the startup disk, Disk Utility makes encrypted disk images and can encrypt external drives, and Preview can put an open password on a PDF. Finder itself has no encrypt command.'
  - q: 'Do I need macFUSE to encrypt files on a Mac?'
    a: 'Only for some tools. VeraCrypt needs macFUSE or FUSE-T, and recommends FUSE-T on Apple silicon. Cryptomator can use either, or WebDAV with no extra software. FileVault, disk images, Encrypto and Stillroom Vault need neither.'
  - q: 'Is FileVault enough, or do I need an encryption app?'
    a: 'FileVault is enough for a lost or stolen Mac. It stops protecting your files once you log in, and it doesn''t cover copies you send or back up elsewhere. An app adds a second lock for those cases.'
  - q: 'What is the best way to encrypt a single file on a Mac to send someone?'
    a: 'Put it in an encrypted disk image, use Encrypto (free, Mac and Windows), or add an open password to a PDF in Preview. Send the password a different way from the file.'
sources:
  - label: 'Apple: Protect data on your Mac with FileVault'
    url: 'https://support.apple.com/guide/mac-help/protect-data-on-your-mac-with-filevault-mh11785/mac'
  - label: 'Apple Platform Security: Volume encryption with FileVault in macOS'
    url: 'https://support.apple.com/guide/security/volume-encryption-with-filevault-sec4c6dc1b6e/web'
  - label: 'Apple: Create a disk image using Disk Utility on Mac'
    url: 'https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac'
  - label: 'Apple: Encrypt and protect a storage device with Disk Utility'
    url: 'https://support.apple.com/guide/disk-utility/encrypt-a-disk-dskutl35612/mac'
  - label: 'Cryptomator: Pricing'
    url: 'https://cryptomator.org/pricing/'
  - label: 'Cryptomator docs: Volume type'
    url: 'https://docs.cryptomator.org/desktop/volume-type/'
  - label: 'Cryptomator: Download for macOS'
    url: 'https://cryptomator.org/downloads/mac/'
  - label: 'VeraCrypt: Downloads'
    url: 'https://veracrypt.io/en/Downloads.html'
  - label: 'MacPaw: Encrypto'
    url: 'https://macpaw.com/encrypto'
  - label: 'Mac App Store: Encrypto'
    url: 'https://apps.apple.com/us/app/encrypto-secure-your-files/id935235287?mt=12'
  - label: 'AxCrypt: Pricing'
    url: 'https://axcrypt.net/pricing/'
  - label: 'AxCrypt: Release notes'
    url: 'https://axcrypt.net/information/release-notes/'
  - label: 'AxCrypt: Open source'
    url: 'https://axcrypt.net/open-source/'
  - label: 'Picocrypt on GitHub (archived)'
    url: 'https://github.com/Picocrypt/Picocrypt'
---

## First, which job do you have?

"Encryption software" covers at least four different jobs on a Mac:

- **Keep the whole Mac safe if it's lost or stolen.** That's whole-disk encryption.
- **Keep files safe in a cloud folder** so the provider can't read them.
- **Lock a drive or a set of files** behind their own password, to carry or store.
- **Keep private things sealed on one Mac** while you use it every day.

Most people need the first, and one of the others. Pick by job, not by which app has the longest feature list.

## The tools at a glance

Prices and versions as checked on 30 October 2026.

| Tool | Price | What it encrypts | Cloud and sync | Open source | Notes |
|---|---|---|---|---|---|
| FileVault | Free, built in | The startup disk | n/a | No | Turn it on first |
| Disk Utility | Free, built in | Disk images; external drives (after erasing) | None; copy the file anywhere | No | Any Mac |
| Cryptomator | Free on desktop; paid mobile apps; Hub for teams | Files and names, in a vault folder | Made for it | Yes | macOS 11 or later; macFUSE, FUSE-T or WebDAV |
| VeraCrypt | Free | Containers, partitions, drives | None built in | Yes | Needs macFUSE or FUSE-T; macOS 12 or later |
| Encrypto (MacPaw) | Free | Single files and folders, to send | None; share the file | No | Mac and Windows; last Mac update August 2024 |
| AxCrypt | Limited free plan; paid subscriptions | Single files | None built in | Partly | Mac, Windows, Linux |
| Stillroom Vault | Free for 25 items; $39 once; Family $79 for 5 | Files, notes, passwords, two-factor codes | None; never goes online | Source available (FSL) | Apple silicon, macOS 26 or later |

Picocrypt, often recommended for small encrypted files, was archived by its developer in September 2025 and is now read-only on GitHub. We've left it out because it's no longer maintained.

## FileVault: turn it on first

FileVault is Apple's whole-disk encryption, and it belongs on every Mac. On Apple silicon your data is already encrypted in hardware; FileVault ties the key to your login password, so a stolen Mac can't be read without it. It's free, quick to turn on, and you choose either your iCloud account or a recovery key as the way back in.

Its limit: once you log in, everything is open to whoever is at the keyboard, and files you copy off the Mac leave unencrypted. [FileVault vs an encrypted vault](/compare/filevault/) covers what it does and doesn't protect in detail.

## Disk Utility: encrypted disk images and drives

Every Mac can make an encrypted disk image: one file that opens, with a password, as a drive in Finder. It holds any kind of file and stays encrypted wherever you copy it. Disk Utility can also encrypt an external drive with a password, though Apple says the drive has to be erased first.

It's the best free answer for a set of files you open now and then, or a bundle to hand someone on a USB stick. While mounted, it's an ordinary drive, open to anything on the Mac until you eject it. Our [disk image comparison](/compare/encrypted-disk-image/) and [folder guide](/guides/password-protect-a-folder-on-mac/) go step by step.

## Cryptomator: for files in the cloud

Cryptomator encrypts files, names included, inside a folder your cloud service syncs, so the provider only ever stores encrypted copies. It's free and open source on the desktop, with apps for iPhone and Android (free to read; writing is a one-time purchase per platform) and Cryptomator Hub for teams. The Mac app needs macOS 11 or later.

To show an unlocked vault as a drive, Cryptomator on a Mac can use macFUSE, FUSE-T (marked experimental in its docs) or WebDAV, which needs no extra software. Pick it when you need the same encrypted files on several devices. See [Stillroom Vault vs Cryptomator](/compare/cryptomator/).

## VeraCrypt: for drives and other systems

VeraCrypt is free, open source disk encryption for Windows, macOS and Linux. It makes encrypted containers, encrypts partitions and drives, and offers hidden volumes. Version 1.26.30 for macOS came out on 24 October 2026, and it supports macOS 12 or later.

On a Mac it needs a FUSE layer installed alongside it: there's a build for macFUSE and one for FUSE-T, and VeraCrypt recommends the FUSE-T build on Apple silicon. Pick it when an encrypted drive has to open on more than one operating system. See [Stillroom Vault vs VeraCrypt](/compare/veracrypt/).

## Encrypto: one file to send

Encrypto, from MacPaw, is a small free app that adds AES-256 encryption to a file or folder so you can send it by Mail, AirDrop, Messages or a cloud link, with an optional password hint. A Windows version lets the other person open it there. It needs no extra system software.

It does one job simply. It isn't for storing many files you work with, and the Mac version was last updated in August 2024 (version 1.4.3, which added native Apple silicon support), so it isn't changing much. For a PDF, Preview's open password does the same job with nothing to install; see [encrypt a PDF on a Mac](/guides/encrypt-pdf-on-mac/), or [encrypt a zip file](/guides/encrypt-zip-file-on-mac/) for a bundle.

## AxCrypt: file-by-file, on several systems

AxCrypt encrypts single files and runs on Windows, macOS and Linux. Its Mac app is actively updated (the release notes list a macOS release on 29 October 2026). The free plan is limited, and Premium and Business are paid subscriptions that lift its limits and add features such as secured folders. AxCrypt publishes part of its code (its .NET desktop code) as open source.

It suits people who want file-by-file encryption that works the same on several systems, and don't mind a subscription. Check its pricing page for current limits, which change.

## Stillroom Vault: a private vault on one Mac

Stillroom Vault is our app, so read this part with that in mind. It's for the job the others handle awkwardly: private things you use often, on a Mac that's often unlocked.

- **Files, notes, passwords and two-factor codes in one place.** Each item is sealed on its own with [AES-256-GCM](/learn/aes-256-gcm/) and a fresh key, under a password stretched with [Argon2id](/learn/argon2id/) (512 MB).
- **It locks itself:** after a time you choose, when the Mac sleeps, or with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> from any app.
- **Viewing doesn't write a decrypted copy to disk.** Built-in viewers handle PDFs, images, text, sketches and email, audio and video stream from the sealed file, and other previews go to a RAM disk. Edit in Place uses the RAM disk too, though the app you edit in may keep copies of its own.
- **It never goes online,** and it needs no file system extension.
- **More ways back in:** a recovery key, a printable [emergency kit](/features/emergency-kit/), Touch ID, and optional [Lock to this Mac](/features/lock-to-this-mac/).

Its limits, plainly:

- **One Mac only.** No sync, no phone app, no Windows. Apple silicon and macOS 26 or later.
- **No independent security audit yet.** The [format is public](/format/), and a short MIT-licensed script opens a vault without the app.
- **Source available, not open source.** The code is published under the FSL, which lets you read and build it but isn't an open source licence.
- **A strong password is the real boundary.** Stillroom refuses guessable ones, but it can't protect against malware with admin rights while the vault is open, and it can't recover a forgotten password.
- **It works alongside FileVault, not instead of it.** FileVault keeps deleted originals unreadable, and Stillroom warns when it's off.

If you keep passwords there too, [offline password managers for Mac](/compare/offline-password-manager-mac/) compares it with the alternatives.

## How to choose

- **Everyone:** turn on FileVault. It's free and covers a lost or stolen Mac.
- **A few files you open now and then:** an encrypted disk image. Free, built in, nothing to install.
- **Files you need on your phone or another computer, through a cloud:** Cryptomator.
- **A USB stick or external drive that must open on Windows or Linux too:** VeraCrypt. A Mac-only drive can be encrypted in Disk Utility.
- **One file to send someone:** a disk image, Encrypto, or a PDF with an open password. Send the password separately.
- **Private files, notes and passwords you use often, on one Mac, with nothing online:** a vault app such as Stillroom Vault, on top of FileVault.
- **If you just want files out of sight,** know that hiding isn't encryption; [hide files on a Mac](/guides/hide-files-on-mac/) explains the difference.

Whatever you choose, keep a backup you've tested, and keep the password or recovery key somewhere other than the Mac. Every tool on this page, ours included, means it when it says a forgotten password can't be recovered.
